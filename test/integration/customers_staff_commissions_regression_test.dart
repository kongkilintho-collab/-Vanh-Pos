// Live regression coverage for Day 3 P1: Customer CRM, Staff management,
// and the Commission ledger. Uses the same live Supabase project and QA
// fixture accounts as the other integration tests in this directory --
// see business_repository_regression_test.dart's header for setup
// details and the skip-when-unconfigured behavior, which this file
// mirrors.
//
// The existing SEC-CRITICAL privilege-escalation guards (ADMIN cannot
// self-escalate to OWNER, cannot demote the real OWNER, sole OWNER cannot
// demote themselves) are NOT duplicated here -- they're already covered
// by business_repository_regression_test.dart and are re-run as part of
// the full regression gate. This file adds one more OWNER-protection
// check specific to staff management's deactivate path (setActive),
// which that file doesn't cover.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/customers_staff_commissions_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/commissions/data/commission_repository.dart';
import 'package:beauty_clinic_pos/features/customers/data/customer_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/features/staff/data/staff_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/commission_status.dart';
import 'package:beauty_clinic_pos/shared/models/customer.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project seeded with the '
    'QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  group('Customers', () {
    test('CASHIER+ can create and read a customer; cross-tenant read is blocked', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner).business.id;

      final repo = CustomerRepository(client);
      final created = await repo.create(_blankCustomer(businessAId, 'CRM Test Customer ${_uuid.v4()}'));

      final list = await repo.listForBusiness(businessAId, query: created.name);
      expect(list.map((c) => c.id), contains(created.id));
      await client.auth.signOut();

      // A caller with zero membership anywhere cannot see the real row --
      // not User B (a real ADMIN of Business A from earlier sessions, who
      // would legitimately see it) or User A again (the owner), but a
      // genuinely unrelated, unauthenticated caller.
      final visibleToOutsider =
          await client.from('customers').select('id').eq('id', created.id);
      expect(visibleToOutsider, isEmpty);
    });

    test('spoofing a business_id the caller has no membership in is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);

      // A syntactically valid but unrelated business_id -- not Business B,
      // since User A is a real CASHIER there (from the Staff tests' own
      // fixture setup) and would legitimately be allowed to insert.
      final unrelatedBusinessId = _uuid.v4();
      await expectLater(
        client.from('customers').insert({'business_id': unrelatedBusinessId, 'name': 'Spoofed Customer'}),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );
      await client.auth.signOut();
    });

    test('customer_notes: insert allowed, no update/delete capability exists (RLS)', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner).business.id;

      final repo = CustomerRepository(client);
      final customer = await repo.create(_blankCustomer(businessAId, 'Notes Test Customer ${_uuid.v4()}'));
      await repo.addNote(businessId: businessAId, customerId: customer.id, note: 'First visit note');

      final notes = await repo.listNotes(customer.id);
      expect(notes, isNotEmpty);
      final noteId = notes.first['id'] as String;

      // No UPDATE policy on customer_notes -- a raw update must affect 0 rows.
      final updateResult =
          await client.from('customer_notes').update({'note': 'tampered'}).eq('id', noteId).select();
      expect(updateResult, isEmpty);

      // No DELETE policy either.
      final deleteResult = await client.from('customer_notes').delete().eq('id', noteId).select();
      expect(deleteResult, isEmpty);

      final stillThere = await client.from('customer_notes').select('note').eq('id', noteId).single();
      expect(stillThere['note'], 'First visit note');
      await client.auth.signOut();
    });
  });

  group('Staff', () {
    test('ADMIN resolves a real email to a user_id; unknown email returns null', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessAId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.admin).business.id;

      final repo = StaffRepository(client);
      final found = await repo.findInvitableUserId(businessId: businessAId, email: _ownerAEmail);
      expect(found, isNotNull);

      final notFound =
          await repo.findInvitableUserId(businessId: businessAId, email: 'nobody-${_uuid.v4()}@nowhere.invalid');
      expect(notFound, isNull);
      await client.auth.signOut();
    });

    test('a real CASHIER-rank member cannot resolve invite candidates', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // Fixture: ensure User A has a real CASHIER membership in Business B
      // (idempotent upsert via invite_business_member).
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final userAId = client.auth.currentUser!.id;
      await client.auth.signOut();

      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner).business.id;
      await client.rpc('invite_business_member', params: {
        'p_business_id': businessBId,
        'p_user_id': userAId,
        'p_role': 'CASHIER',
      });
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        StaffRepository(client).findInvitableUserId(businessId: businessBId, email: _ownerBEmail),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
      );
      await client.auth.signOut();
    });

    test('ADMIN+ can change an eligible (non-owner) member\'s role and deactivate/reactivate them', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final userAMemberships = await BusinessRepository(client).myMemberships();
      final businessAId = userAMemberships.firstWhere((m) => m.role == BusinessRole.owner).business.id;
      final userBId =
          (await client.from('business_members').select('user_id').eq('business_id', businessAId).eq('role', 'ADMIN'))
              .first['user_id'] as String;

      final repo = StaffRepository(client);
      try {
        // Role change: ADMIN -> MANAGER -> back to ADMIN (restore, since
        // other tests/files rely on User B being ADMIN of Business A).
        await repo.updateRole(businessId: businessAId, userId: userBId, role: 'MANAGER');
        var row = await client
            .from('business_members')
            .select('role')
            .eq('business_id', businessAId)
            .eq('user_id', userBId)
            .single();
        expect(row['role'], 'MANAGER');

        // Deactivate / reactivate.
        await repo.setActive(businessId: businessAId, userId: userBId, active: false);
        row = await client
            .from('business_members')
            .select('active')
            .eq('business_id', businessAId)
            .eq('user_id', userBId)
            .single();
        expect(row['active'], false);

        await repo.setActive(businessId: businessAId, userId: userBId, active: true);
        row = await client
            .from('business_members')
            .select('active')
            .eq('business_id', businessAId)
            .eq('user_id', userBId)
            .single();
        expect(row['active'], true);
      } finally {
        // Always restore, even if an assertion above failed.
        await repo.updateRole(businessId: businessAId, userId: userBId, role: 'ADMIN');
        await repo.setActive(businessId: businessAId, userId: userBId, active: true);
      }
      await client.auth.signOut();
    });

    test('OWNER cannot be deactivated by a non-owner ADMIN', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessAId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.admin).business.id;
      final userAId =
          (await client.from('business_members').select('user_id').eq('business_id', businessAId).eq('role', 'OWNER'))
              .first['user_id'] as String;

      final result = await client
          .from('business_members')
          .update({'active': false})
          .eq('business_id', businessAId)
          .eq('user_id', userAId)
          .select();
      expect(result, isEmpty, reason: 'RLS must block a non-owner ADMIN deactivating the real OWNER');

      final stillActive = await client
          .from('business_members')
          .select('active')
          .eq('business_id', businessAId)
          .eq('user_id', userAId)
          .single();
      expect(stillActive['active'], true);
      await client.auth.signOut();
    });
  });

  group('Commissions', () {
    test('Customer -> Sale -> Staff -> Commission: end-to-end via complete_sale, '
        'then ADMIN+ can approve it and a CASHIER-rank member cannot', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId =
          (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner).business.id;
      final userAId =
          (await client.from('business_members').select('user_id').eq('business_id', businessBId).eq('role', 'CASHIER'))
              .first['user_id'] as String;

      // Customer.
      final customer = await CustomerRepository(client)
          .create(_blankCustomer(businessBId, 'Commission Chain Customer ${_uuid.v4()}'));

      // Service with a known 20% commission.
      final service = await client
          .from('services')
          .insert({
            'business_id': businessBId,
            'name': 'Commission Chain Service',
            'price': 400000,
            'commission_value': 20,
          })
          .select()
          .single();

      // Sale, attributing the service to User A (a real CASHIER member of
      // Business B) for commission.
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessBId);
      final sale = await posRepo.completeSale(
        businessId: businessBId,
        branchId: branchId,
        customerId: customer.id,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': userAId,
            'name_snapshot': 'Commission Chain Service',
            'quantity': 1,
            'unit_price': '400000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '400000',
        idempotencyKey: _uuid.v4(),
      );

      final commissionRows =
          await client.from('commissions').select().eq('sale_id', sale['id'] as String);
      expect(commissionRows, hasLength(1));
      final commissionRow = (commissionRows as List).first as Map<String, dynamic>;
      expect(commissionRow['staff_id'], userAId);
      // 20% of 400,000. Compared as Decimal, not raw string -- Postgres's
      // numeric JSON serialization doesn't guarantee a fixed trailing-zero
      // count, so an exact string match is a test-fragility trap, not a
      // real correctness check.
      expect(Decimal.parse(commissionRow['commission_amount'].toString()), Decimal.parse('80000'));
      expect(commissionRow['status'], 'PENDING');
      final commissionId = commissionRow['id'] as String;

      // member can read own-business commission rows.
      final readable = await CommissionRepository(client).listForBusiness(businessBId);
      expect(readable.map((c) => c.id), contains(commissionId));

      // cross-tenant: a business_id the caller has no membership in at
      // all returns empty, not another business's data or an error.
      final crossTenant =
          await client.from('commissions').select('id').eq('business_id', _uuid.v4());
      expect(crossTenant, isEmpty);
      await client.auth.signOut();

      // A CASHIER-rank member cannot approve it.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final rejected = await client
          .from('commissions')
          .update({'status': 'APPROVED'})
          .eq('id', commissionId)
          .select();
      expect(rejected, isEmpty, reason: 'RLS must block a CASHIER-rank member from updating commission status');
      await client.auth.signOut();

      // The OWNER (ADMIN+) can approve it.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      await CommissionRepository(client).updateStatus(
        id: commissionId,
        businessId: businessBId,
        status: CommissionStatus.approved,
      );
      final approved =
          await client.from('commissions').select('status').eq('id', commissionId).single();
      expect(approved['status'], 'APPROVED');
      await client.auth.signOut();
    });
  });
}

Customer _blankCustomer(String businessId, String name) {
  return Customer(
    id: '',
    businessId: businessId,
    name: name,
    totalSpent: Decimal.zero,
    visitCount: 0,
    active: true,
  );
}
