// Live regression coverage for Day 6 Security Hardening findings F1-F4
// (see supabase/migrations/0021_revoke_anon_execute_on_onboarding_and_checkout.sql,
// 0022_protect_financial_snapshot_columns.sql,
// 0023_complete_sale_customer_integrity.sql).
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/security_hardening_regression_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0021-0023 applied and seeded with the QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

/// A raw, deliberately-anonymous POST to a PostgREST RPC endpoint using
/// only the anon key -- no Supabase session, no Authorization from a
/// signed-in user. Built on dart:io's HttpClient (no extra package
/// dependency) rather than the Supabase SDK, since the SDK always attaches
/// whatever session is current; this needs a request that never carries
/// one. This is the only way to distinguish "Postgres itself rejected the
/// call" (42501, the ACL layer) from "the function ran and rejected it
/// internally" (F3 requires proving the former, not the latter -- the
/// same technique 0019's own commit used to originally discover this
/// class of gap).
Future<Map<String, dynamic>> _anonRpc(String function, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/$function'));
    request.headers.set('apikey', Env.supabaseAnonKey);
    request.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    return {'status': response.statusCode, 'body': responseBody};
  } finally {
    client.close();
  }
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  group('F1: financial/snapshot column protection', () {
    test('a MANAGER+ direct update to sales.total_amount is rejected; status remains updatable', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F1 Test Service ${_uuid.v4()}', 'price': 100000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F1 Test Service',
            'quantity': 1,
            'unit_price': '100000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '100000',
        idempotencyKey: _uuid.v4(),
      );

      await expectLater(
        client.from('sales').update({'total_amount': '1'}).eq('id', sale['id'] as String),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify financial, attribution, or identity fields'),
        )),
      );

      final unchanged = await client.from('sales').select('total_amount').eq('id', sale['id'] as String).single();
      expect(Decimal.parse(unchanged['total_amount'].toString()), Decimal.parse('100000'));

      // Legitimate existing behavior: a status-only change is still allowed
      // by the trigger (RLS's own MANAGER+ floor on sales_update is
      // untouched and still applies).
      await client.from('sales').update({'status': 'COMPLETED'}).eq('id', sale['id'] as String);

      await client.auth.signOut();
    });

    test('a direct update to payments.amount is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F1 Payment Test Service ${_uuid.v4()}', 'price': 50000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F1 Payment Test Service',
            'quantity': 1,
            'unit_price': '50000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '50000',
        idempotencyKey: _uuid.v4(),
      );

      final payment = await client.from('payments').select('id').eq('business_id', businessAId).order('created_at', ascending: false).limit(1).single();

      await expectLater(
        client.from('payments').update({'amount': '1'}).eq('id', payment['id'] as String),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify financial or identity fields on an existing payment'),
        )),
      );

      await client.auth.signOut();
    });

    test('a direct update to commissions.commission_amount or staff_id is rejected; status remains updatable', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final userAId = (await client
              .from('business_members')
              .select('user_id')
              .eq('business_id', businessBId)
              .eq('role', 'CASHIER'))
          .first['user_id'] as String;

      final service = await client
          .from('services')
          .insert({'business_id': businessBId, 'name': 'F1 Commission Test Service ${_uuid.v4()}', 'price': 200000, 'commission_value': 10})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessBId);
      final sale = await posRepo.completeSale(
        businessId: businessBId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': userAId,
            'name_snapshot': 'F1 Commission Test Service',
            'quantity': 1,
            'unit_price': '200000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '200000',
        idempotencyKey: _uuid.v4(),
      );

      final commission = await client.from('commissions').select('id').eq('sale_id', sale['id'] as String).single();

      await expectLater(
        client.from('commissions').update({'commission_amount': '999999'}).eq('id', commission['id'] as String),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify commission amount, rate, or attribution'),
        )),
      );

      // Legitimate existing behavior: ADMIN+ status transitions still work.
      await client.from('commissions').update({'status': 'APPROVED'}).eq('id', commission['id'] as String);
      final approved = await client.from('commissions').select('status').eq('id', commission['id'] as String).single();
      expect(approved['status'], 'APPROVED');

      await client.auth.signOut();
    });
  });

  group('F2: customer lifetime metrics protection', () {
    test('a direct update to customers.total_spent is rejected, but complete_sale still updates it correctly', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      final customer = await client
          .from('customers')
          .insert({'business_id': businessAId, 'name': 'F2 Test Customer ${_uuid.v4()}'})
          .select()
          .single();
      final customerId = customer['id'] as String;

      await expectLater(
        client.from('customers').update({'total_spent': '999999'}).eq('id', customerId),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('total_spent, visit_count, and last_visit_at can only be updated by complete_sale'),
        )),
      );

      final unchanged = await client.from('customers').select('total_spent, visit_count').eq('id', customerId).single();
      expect(Decimal.parse(unchanged['total_spent'].toString()), Decimal.zero);
      expect(unchanged['visit_count'], 0);

      // The legitimate internal path: complete_sale must still update these
      // three columns for a real sale attributed to this customer.
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F2 Test Service ${_uuid.v4()}', 'price': 75000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: customerId,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F2 Test Service',
            'quantity': 1,
            'unit_price': '75000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '75000',
        idempotencyKey: _uuid.v4(),
      );

      final afterSale = await client.from('customers').select('total_spent, visit_count, last_visit_at').eq('id', customerId).single();
      expect(Decimal.parse(afterSale['total_spent'].toString()), Decimal.parse('75000'));
      expect(afterSale['visit_count'], 1);
      expect(afterSale['last_visit_at'], isNotNull);

      await client.auth.signOut();
    });
  });

  group('F3: RPC execute privilege hardening', () {
    test('anonymous calls to create_business_with_owner, invite_business_member, and complete_sale '
        'are rejected by Postgres itself (42501), not the function body', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }

      final createResult = await _anonRpc('create_business_with_owner', {'p_name': 'Should Never Be Created'});
      expect(createResult['status'], 401);
      expect(createResult['body'], contains('42501'));
      expect(createResult['body'], contains('permission denied for function create_business_with_owner'));

      final inviteResult = await _anonRpc('invite_business_member', {
        'p_business_id': '00000000-0000-0000-0000-000000000000',
        'p_user_id': '00000000-0000-0000-0000-000000000000',
        'p_role': 'CASHIER',
      });
      expect(inviteResult['status'], 401);
      expect(inviteResult['body'], contains('42501'));
      expect(inviteResult['body'], contains('permission denied for function invite_business_member'));

      final saleResult = await _anonRpc('complete_sale', {
        'p_business_id': '00000000-0000-0000-0000-000000000000',
        'p_branch_id': null,
        'p_customer_id': null,
        'p_items': <dynamic>[],
        'p_discount_amount': 0,
        'p_tax_amount': 0,
        'p_payment_method': 'CASH',
        'p_paid_amount': 0,
        'p_idempotency_key': null,
      });
      expect(saleResult['status'], 401);
      expect(saleResult['body'], contains('42501'));
      expect(saleResult['body'], contains('permission denied for function complete_sale'));
    });

    test('an authenticated caller still reaches create_business_with_owner\'s own validation, past the ACL', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);

      // Deliberately invalid input (blank name) instead of a real business
      // name -- this proves the authenticated caller passes the ACL and
      // reaches the function's own body (its "Business name is required"
      // validation fires), without ever creating a persistent business.
      // Every other RPC's legitimate-call path is already exercised by the
      // frozen suites (complete_sale by pos_checkout_regression_test.dart,
      // invite_business_member by the fixture setup in this file and in
      // customers_staff_commissions_regression_test.dart/
      // staff_invite_lookup_regression_test.dart) -- create_business_with_owner
      // has no such reusable fixture path, and creating a real business here
      // is a one-way action (no delete policy exists on businesses), so this
      // is the only side-effect-free way to prove its authenticated path
      // still works post-0021.
      await expectLater(
        client.rpc('create_business_with_owner', params: {'p_name': ''}),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Business name is required'))),
      );

      await client.auth.signOut();
    });

    test('invite_business_member still rejects an under-ranked authenticated caller with its own message', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // User A is a real CASHIER of Business B (established fixture from
      // earlier Day 3/4 tests) -- below the ADMIN floor.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        client.rpc('invite_business_member', params: {
          'p_business_id': businessBId,
          'p_user_id': client.auth.currentUser!.id,
          'p_role': 'CASHIER',
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission to add members'))),
      );

      await client.auth.signOut();
    });
  });

  group('F4: complete_sale customer tenant validation', () {
    test('a cross-tenant customer_id is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final customerInB = await client
          .from('customers')
          .insert({'business_id': businessBId, 'name': 'F4 Cross Tenant Customer ${_uuid.v4()}'})
          .select()
          .single();
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F4 Test Service ${_uuid.v4()}', 'price': 10000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      await expectLater(
        posRepo.completeSale(
          businessId: businessAId,
          branchId: branchId,
          customerId: customerInB['id'] as String,
          items: [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F4 Test Service',
              'quantity': 1,
              'unit_price': '10000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '10000',
          idempotencyKey: _uuid.v4(),
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found in this business'))),
      );

      await client.auth.signOut();
    });

    test('a nonexistent customer_id is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F4 Nonexistent Test Service ${_uuid.v4()}', 'price': 10000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      await expectLater(
        posRepo.completeSale(
          businessId: businessAId,
          branchId: branchId,
          customerId: _uuid.v4(),
          items: [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F4 Nonexistent Test Service',
              'quantity': 1,
              'unit_price': '10000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '10000',
          idempotencyKey: _uuid.v4(),
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found in this business'))),
      );

      await client.auth.signOut();
    });

    test('a null customer_id preserves existing behavior (walk-in sale succeeds)', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F4 Walkin Test Service ${_uuid.v4()}', 'price': 10000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F4 Walkin Test Service',
            'quantity': 1,
            'unit_price': '10000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '10000',
        idempotencyKey: _uuid.v4(),
      );

      expect(sale['customer_id'], isNull);
      expect(sale['status'], 'COMPLETED');

      await client.auth.signOut();
    });
  });
}
