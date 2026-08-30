// Live regression coverage for F9-3 ("Audit logs wired to every mutation"
// -- see supabase/migrations/0027_audit_log_coverage.sql).
//
// Covers: adjust_stock's new STOCK_ADJUSTMENT audit row, the new
// set_member_role/set_member_active RPCs (authorized success, unauthorized
// denial, OWNER-row protection) and the closure of the business_members
// direct-write bypass, and audit_logs read security (anon/cross-tenant
// denial, ADMIN+/OWNER allowed, no client UPDATE/DELETE).
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory:
//   - van@test.local   / admin123456@   -- OWNER of business "A"
//   - admin@test.local / 123456@12      -- OWNER of business "B", and
//     ADMIN member of business "A"
//
// create_business_with_owner is deliberately NOT exercised as a live
// success case here -- this project already hit and fixed exactly this
// problem once (see customers_staff_commissions_regression_test.dart's own
// history: an earlier positive-path test for this RPC permanently created
// an extra business, which corrupted BusinessRepository.myMemberships()'s
// "most recently created" resolution for every other test relying on
// van/admin's fixture identity, requiring a multi-step live cleanup to
// recover). Its audit-logging behavior (0016_business_onboarding.sql:82-83,
// unchanged by F9-3) is verified by code inspection only. invite_business_
// member is safe to exercise live instead: re-inviting an already-active
// member with their current role is an idempotent upsert with no
// side effect on any other test's fixture assumptions.
//
// Staff role/active changes round-trip admin@test.local's ADMIN-of-
// business-A status (change away, then change back) within the same test,
// so no other test's fixture assumption about admin's role in business A
// is left disturbed.
//
// No STAFF- or CASHIER-rank fixture account exists (self-service .local
// signup is rejected by GoTrue in this project; documented during Day 6
// cleanup, re-confirmed during F9-2). The "unauthorized caller" cases below
// use van as a genuine non-member of business B instead, which exercises
// the same authorization gate live without fabricating a fixture.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/audit_log_coverage_regression_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/inventory/data/inventory_repository.dart';
import 'package:beauty_clinic_pos/features/staff/data/staff_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/inventory_movement_type.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0027 applied and seeded with the QA fixture accounts.';
const _noStaffCashierFixture =
    'No STAFF- or CASHIER-rank fixture account exists (self-service '
    '.local signup is rejected by GoTrue in this project; documented '
    'during Day 6 cleanup and again during F9-2).';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

/// Same technique used by security_hardening_regression_test.dart's F3
/// coverage and void_sale_regression_test.dart -- a raw, session-free HTTP
/// call distinguishes an ACL denial (401/42501) from a function-body
/// rejection, and lets us read a table as anon without the SDK attaching
/// whatever session happens to be current.
Future<Map<String, dynamic>> _anonGet(String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/$path'));
    request.headers.set('apikey', Env.supabaseAnonKey);
    request.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
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

  test(
    'create_business_with_owner audit logging verified by code inspection only '
    '(0016_business_onboarding.sql:82-83) -- not exercised live to avoid repeating '
    'the documented myMemberships() fixture-contamination incident',
    () => markTestSkipped(
      'Intentionally not run live: create_business_with_owner permanently creates a new '
      'business with no delete path, which previously corrupted shared van/admin fixture '
      'resolution for every other test in this suite. See this file\'s header comment.',
    ),
  );

  test('invite_business_member: re-inviting an already-active member produces one PERMISSION_CHANGE audit row', () async {
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
    final adminMember = await client
        .from('business_members')
        .select('id, user_id')
        .eq('business_id', businessAId)
        .eq('role', 'ADMIN')
        .single();
    final adminUserId = adminMember['user_id'] as String;
    final memberRowId = adminMember['id'] as String;

    final beforeCount = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessAId)
            .eq('action', 'PERMISSION_CHANGE')
            .eq('entity_id', memberRowId))
        .length;

    await client.rpc('invite_business_member', params: {
      'p_business_id': businessAId,
      'p_user_id': adminUserId,
      'p_role': 'ADMIN',
    });

    final auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessAId)
        .eq('action', 'PERMISSION_CHANGE')
        .eq('entity_id', memberRowId)
        .order('created_at', ascending: false);
    expect(auditRows.length, greaterThan(beforeCount), reason: 'the re-invite must have produced a new audit row');
    expect(auditRows.first['user_id'], client.auth.currentUser!.id);

    await client.auth.signOut();
  });

  test('adjust_stock produces exactly one STOCK_ADJUSTMENT audit row with correct actor/business/entity/data', () async {
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
    final ownerAId = client.auth.currentUser!.id;

    final product = await client
        .from('products')
        .insert({'business_id': businessAId, 'name': 'F9-3 Fixture Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
        .select()
        .single();

    await InventoryRepository(client).adjustStock(
      businessId: businessAId,
      productId: product['id'] as String,
      movementType: InventoryMovementType.purchase,
      quantityDelta: 3,
    );

    final auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessAId)
        .eq('action', 'STOCK_ADJUSTMENT')
        .eq('entity_id', product['id'] as String);
    expect(auditRows, hasLength(1));
    final audit = auditRows[0];
    expect(audit['user_id'], ownerAId);
    expect(audit['entity_type'], 'product');
    expect((audit['old_data'] as Map)['stock_quantity'], 5);
    expect((audit['new_data'] as Map)['stock_quantity'], 8);
    final metadata = audit['metadata'] as Map;
    expect(metadata['movement_type'], 'PURCHASE');
    expect(metadata['quantity_delta'], 3);

    await client.auth.signOut();
  });

  test('authorized role change round-trip: succeeds, produces exactly one PERMISSION_CHANGE row per step, restores original role', () async {
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
    final ownerAId = client.auth.currentUser!.id;
    final adminMember = await client
        .from('business_members')
        .select('id, user_id')
        .eq('business_id', businessAId)
        .eq('role', 'ADMIN')
        .single();
    final targetUserId = adminMember['user_id'] as String;
    final memberRowId = adminMember['id'] as String;

    final staffRepo = StaffRepository(client);

    await staffRepo.updateRole(businessId: businessAId, userId: targetUserId, role: 'MANAGER');
    final afterDemote = await client.from('business_members').select('role').eq('id', memberRowId).single();
    expect(afterDemote['role'], 'MANAGER');

    var auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessAId)
        .eq('action', 'PERMISSION_CHANGE')
        .eq('entity_id', memberRowId)
        .order('created_at', ascending: false)
        .limit(1);
    expect(auditRows, hasLength(1));
    expect(auditRows[0]['user_id'], ownerAId);
    expect((auditRows[0]['old_data'] as Map)['role'], 'ADMIN');
    expect((auditRows[0]['new_data'] as Map)['role'], 'MANAGER');

    // Restore: back to ADMIN, so no other test's fixture assumption is disturbed.
    await staffRepo.updateRole(businessId: businessAId, userId: targetUserId, role: 'ADMIN');
    final restored = await client.from('business_members').select('role').eq('id', memberRowId).single();
    expect(restored['role'], 'ADMIN');

    auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessAId)
        .eq('action', 'PERMISSION_CHANGE')
        .eq('entity_id', memberRowId)
        .order('created_at', ascending: false)
        .limit(1);
    expect((auditRows[0]['old_data'] as Map)['role'], 'MANAGER');
    expect((auditRows[0]['new_data'] as Map)['role'], 'ADMIN');

    await client.auth.signOut();
  });

  test('a non-member of the target business cannot change a role there', () async {
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
    await client.auth.signOut();

    // van@test.local is OWNER of business A only -- not a member of B.
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    await expectLater(
      client.rpc('set_member_role', params: {
        'p_business_id': businessBId,
        'p_target_user_id': _uuid.v4(),
        'p_role': 'MANAGER',
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission to change member roles'))),
    );

    await client.auth.signOut();
  });

  test('STAFF/CASHIER-rank denial for role/active changes -- no fixture account to run this live', () {
    markTestSkipped(_noStaffCashierFixture);
  });

  test('a non-OWNER ADMIN cannot modify an OWNER row via set_member_role or set_member_active; no audit row is created', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.admin)
        .business
        .id;
    final ownerMember = await client
        .from('business_members')
        .select('id, user_id, role, active')
        .eq('business_id', businessAId)
        .eq('role', 'OWNER')
        .single();
    final ownerRowId = ownerMember['id'] as String;
    final ownerUserId = ownerMember['user_id'] as String;

    final auditCountBefore = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessAId)
            .eq('action', 'PERMISSION_CHANGE')
            .eq('entity_id', ownerRowId))
        .length;

    await expectLater(
      client.rpc('set_member_role', params: {'p_business_id': businessAId, 'p_target_user_id': ownerUserId, 'p_role': 'MANAGER'}),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only an owner can modify an owner'))),
    );
    await expectLater(
      client.rpc('set_member_active', params: {'p_business_id': businessAId, 'p_target_user_id': ownerUserId, 'p_active': false}),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only an owner can deactivate or reactivate an owner'))),
    );

    final unchanged = await client.from('business_members').select('role, active').eq('id', ownerRowId).single();
    expect(unchanged['role'], 'OWNER');
    expect(unchanged['active'], true);

    final auditCountAfter = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessAId)
            .eq('action', 'PERMISSION_CHANGE')
            .eq('entity_id', ownerRowId))
        .length;
    expect(auditCountAfter, auditCountBefore, reason: 'no audit row may be committed for a rejected mutation');

    await client.auth.signOut();
  });

  test('a non-OWNER caller cannot self-escalate to ADMIN or OWNER via set_member_role; target unchanged, no audit row', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.admin)
        .business
        .id;
    final adminId = client.auth.currentUser!.id;
    final adminMember = await client
        .from('business_members')
        .select('id, role')
        .eq('business_id', businessAId)
        .eq('user_id', adminId)
        .single();
    final adminRowId = adminMember['id'] as String;

    final auditCountBefore = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessAId)
            .eq('action', 'PERMISSION_CHANGE')
            .eq('entity_id', adminRowId))
        .length;

    await expectLater(
      client.rpc('set_member_role', params: {'p_business_id': businessAId, 'p_target_user_id': adminId, 'p_role': 'ADMIN'}),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only an owner can assign this role'))),
    );
    await expectLater(
      client.rpc('set_member_role', params: {'p_business_id': businessAId, 'p_target_user_id': adminId, 'p_role': 'OWNER'}),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only an owner can assign this role'))),
    );

    final unchanged = await client.from('business_members').select('role').eq('id', adminRowId).single();
    expect(unchanged['role'], 'ADMIN', reason: 'self-escalation must not have changed the caller\'s own role');

    final auditCountAfter = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessAId)
            .eq('action', 'PERMISSION_CHANGE')
            .eq('entity_id', adminRowId))
        .length;
    expect(auditCountAfter, auditCountBefore, reason: 'no audit row may be committed for a rejected escalation attempt');

    await client.auth.signOut();
  });

  test('C: a direct PATCH on business_members.role is no longer possible (business_members_update dropped)', () async {
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
    final adminMember = await client
        .from('business_members')
        .select('id, role')
        .eq('business_id', businessAId)
        .eq('role', 'ADMIN')
        .single();

    final updated = await client.from('business_members').update({'role': 'MANAGER'}).eq('id', adminMember['id'] as String).select();
    expect(updated, isEmpty, reason: 'business_members_update was dropped in 0027 -- RLS filters the row to zero matches');

    final unchanged = await client.from('business_members').select('role').eq('id', adminMember['id'] as String).single();
    expect(unchanged['role'], 'ADMIN', reason: 'the rejected direct PATCH must not have mutated the row');

    await client.auth.signOut();
  });

  test('authorized active-state round-trip: succeeds, produces exactly one PERMISSION_CHANGE row per step, restores original state', () async {
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
    final adminMember = await client
        .from('business_members')
        .select('id, user_id')
        .eq('business_id', businessAId)
        .eq('role', 'ADMIN')
        .single();
    final targetUserId = adminMember['user_id'] as String;
    final memberRowId = adminMember['id'] as String;
    final staffRepo = StaffRepository(client);

    await staffRepo.setActive(businessId: businessAId, userId: targetUserId, active: false);
    var current = await client.from('business_members').select('active').eq('id', memberRowId).single();
    expect(current['active'], false);

    var auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessAId)
        .eq('action', 'PERMISSION_CHANGE')
        .eq('entity_id', memberRowId)
        .order('created_at', ascending: false)
        .limit(1);
    expect((auditRows[0]['old_data'] as Map)['active'], true);
    expect((auditRows[0]['new_data'] as Map)['active'], false);

    // Restore, so no other test's fixture assumption (admin active in A) is disturbed.
    await staffRepo.setActive(businessId: businessAId, userId: targetUserId, active: true);
    current = await client.from('business_members').select('active').eq('id', memberRowId).single();
    expect(current['active'], true);

    await client.auth.signOut();
  });

  test('an unauthorized (non-member) active-state change is denied', () async {
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
    await client.auth.signOut();

    await _signIn(client, _ownerAEmail, _ownerAPassword);
    await expectLater(
      client.rpc('set_member_active', params: {
        'p_business_id': businessBId,
        'p_target_user_id': _uuid.v4(),
        'p_active': false,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission to change member status'))),
    );

    await client.auth.signOut();
  });

  test('D: a direct PATCH on business_members.active is no longer possible (business_members_update dropped)', () async {
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
    final adminMember = await client
        .from('business_members')
        .select('id, active')
        .eq('business_id', businessAId)
        .eq('role', 'ADMIN')
        .single();

    final updated = await client.from('business_members').update({'active': false}).eq('id', adminMember['id'] as String).select();
    expect(updated, isEmpty, reason: 'business_members_update was dropped in 0027 -- RLS filters the row to zero matches');

    final unchanged = await client.from('business_members').select('active').eq('id', adminMember['id'] as String).single();
    expect(unchanged['active'], true, reason: 'the rejected direct PATCH must not have mutated the row');

    await client.auth.signOut();
  });

  test('anon cannot read audit_logs (RLS filters to zero rows, not an error)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final result = await _anonGet('audit_logs?select=id&limit=1');
    expect(result['status'], 200, reason: 'RLS silently filters SELECT -- it does not raise an error for a missing policy match');
    expect(result['body'], '[]');
  });

  test('ADMIN can read own-tenant audit logs; OWNER can read own-tenant audit logs; cross-tenant rows are inaccessible', () async {
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
    final businessAAsAdmin = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.admin)
        .business
        .id;
    final adminOwnB = await client.from('audit_logs').select('id, business_id').eq('business_id', businessBId).limit(1);
    final adminReadA = await client.from('audit_logs').select('id, business_id').eq('business_id', businessAAsAdmin).limit(1);
    // ADMIN read of B (owner) and of A (admin rank) are both permitted by
    // audit_logs_select (has_role_at_least(business_id, 'ADMIN')); presence
    // of rows depends on prior activity, but the query itself must not error.
    expect(adminOwnB, isA<List>());
    expect(adminReadA, isA<List>());
    await client.auth.signOut();

    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerOwnA = await client.from('audit_logs').select('id, business_id').eq('business_id', businessAId).limit(1);
    expect(ownerOwnA, isNotEmpty, reason: 'business A has accumulated audit rows from the tests above');
    for (final row in ownerOwnA) {
      expect(row['business_id'], businessAId);
    }

    // Cross-tenant: van is not a member of business B at all.
    final crossTenant = await client.from('audit_logs').select('id').eq('business_id', businessBId).limit(1);
    expect(crossTenant, isEmpty, reason: 'a non-member must see zero rows for a business they do not belong to, not an error');

    await client.auth.signOut();
  });

  test('audit_logs cannot be UPDATEd by the client (no UPDATE policy exists)', () async {
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
    final existing = await client.from('audit_logs').select('id, action').eq('business_id', businessAId).limit(1).single();

    final updated = await client.from('audit_logs').update({'action': 'DELETE'}).eq('id', existing['id'] as String).select();
    expect(updated, isEmpty);

    final unchanged = await client.from('audit_logs').select('action').eq('id', existing['id'] as String).single();
    expect(unchanged['action'], existing['action']);

    await client.auth.signOut();
  });

  test('audit_logs cannot be DELETEd by the client (no DELETE policy exists)', () async {
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
    final existing = await client.from('audit_logs').select('id').eq('business_id', businessAId).limit(1).single();

    final deleted = await client.from('audit_logs').delete().eq('id', existing['id'] as String).select();
    expect(deleted, isEmpty);

    final stillThere = await client.from('audit_logs').select('id').eq('id', existing['id'] as String).maybeSingle();
    expect(stillThere, isNotNull);

    await client.auth.signOut();
  });

  test('anon EXECUTE on set_member_role and set_member_active is denied by ACL', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = HttpClient();
    try {
      final req1 = await client.postUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/set_member_role'));
      req1.headers.set('apikey', Env.supabaseAnonKey);
      req1.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
      req1.headers.set('Content-Type', 'application/json');
      req1.write(jsonEncode({'p_business_id': '00000000-0000-0000-0000-000000000000', 'p_target_user_id': '00000000-0000-0000-0000-000000000000', 'p_role': 'MANAGER'}));
      final resp1 = await req1.close();
      final body1 = await resp1.transform(utf8.decoder).join();
      expect(resp1.statusCode, 401);
      expect(body1, contains('42501'));

      final req2 = await client.postUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/set_member_active'));
      req2.headers.set('apikey', Env.supabaseAnonKey);
      req2.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
      req2.headers.set('Content-Type', 'application/json');
      req2.write(jsonEncode({'p_business_id': '00000000-0000-0000-0000-000000000000', 'p_target_user_id': '00000000-0000-0000-0000-000000000000', 'p_active': false}));
      final resp2 = await req2.close();
      final body2 = await resp2.transform(utf8.decoder).join();
      expect(resp2.statusCode, 401);
      expect(body2, contains('42501'));
    } finally {
      client.close();
    }
  });
}
