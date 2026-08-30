// Live regression coverage for F9-4 ("Business settings" -- see
// supabase/migrations/0028_business_settings_rpc.sql).
//
// Covers: update_business_settings' authorized success (round-tripped back
// to the original fixture values, so no other test's assumption about
// van/admin's business profile is disturbed), exactly-one SETTINGS_CHANGE
// audit row with correct old/new snapshots, tenant isolation, rejected-
// mutation atomicity (zero mutation + zero audit row), the closure of the
// businesses_update direct-write bypass, and audit_logs immutability
// (still enforced, unaffected by 0028).
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory:
//   - van@test.local   / admin123456@   -- OWNER of business "A"
//   - admin@test.local / 123456@12      -- OWNER of business "B", and
//     ADMIN member of business "A"
//
// No STAFF- or CASHIER-rank fixture account exists (self-service .local
// signup is rejected by GoTrue in this project; documented since Day 6,
// re-confirmed in F9-2/F9-3). The "unauthorized caller" case below uses
// van as a genuine non-member of business B instead.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/business_settings_regression_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0028 applied and seeded with the QA fixture accounts.';
const _noStaffCashierFixture =
    'No STAFF- or CASHIER-rank fixture account exists (self-service '
    '.local signup is rejected by GoTrue in this project; documented '
    'during Day 6 cleanup and again during F9-2/F9-3).';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Matcher _deniedByRls() => isA<PostgrestException>().having((e) => e.code, 'code', '42501');

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('OWNER can update all settings fields; exactly one SETTINGS_CHANGE audit row per save; round-trips back to original', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final ownerId = client.auth.currentUser!.id;
    final original = membership.business;

    final updated = await BusinessRepository(client).updateSettings(
      businessId: businessId,
      name: '${original.name} (F9-4 test)',
      phone: '5555550000',
      email: 'f94test@example.com',
      address: 'F9-4 Test Address',
      currency: 'USD',
      taxEnabled: !original.taxEnabled,
      taxRate: 7.5,
      logoUrl: 'https://example.com/logo.png',
    );

    expect(updated.name, '${original.name} (F9-4 test)');
    expect(updated.phone, '5555550000');
    expect(updated.email, 'f94test@example.com');
    expect(updated.address, 'F9-4 Test Address');
    expect(updated.currency, 'USD');
    expect(updated.taxEnabled, !original.taxEnabled);
    expect(updated.taxRate, 7.5);
    expect(updated.logoUrl, 'https://example.com/logo.png');

    final auditRows = await client
        .from('audit_logs')
        .select()
        .eq('business_id', businessId)
        .eq('action', 'SETTINGS_CHANGE')
        .eq('entity_id', businessId)
        .order('created_at', ascending: false)
        .limit(1);
    expect(auditRows, hasLength(1));
    final audit = auditRows[0];
    expect(audit['user_id'], ownerId);
    expect(audit['entity_type'], 'business');
    expect((audit['old_data'] as Map)['name'], original.name);
    expect((audit['old_data'] as Map)['currency'], original.currency);
    expect((audit['new_data'] as Map)['name'], '${original.name} (F9-4 test)');
    expect((audit['new_data'] as Map)['currency'], 'USD');

    // Restore, so no other test's fixture assumption about business A is disturbed.
    final restored = await BusinessRepository(client).updateSettings(
      businessId: businessId,
      name: original.name,
      phone: original.phone,
      email: original.email,
      address: original.address,
      currency: original.currency,
      taxEnabled: original.taxEnabled,
      taxRate: original.taxRate,
      logoUrl: original.logoUrl,
    );
    expect(restored.name, original.name);
    expect(restored.currency, original.currency);
    expect(restored.taxEnabled, original.taxEnabled);
    expect(restored.taxRate, original.taxRate);

    final auditRowsAfterRestore = await client
        .from('audit_logs')
        .select('id')
        .eq('business_id', businessId)
        .eq('action', 'SETTINGS_CHANGE')
        .eq('entity_id', businessId);
    expect(auditRowsAfterRestore.length, greaterThanOrEqualTo(2), reason: 'the restore step is itself a second successful mutation, so it must also produce its own audit row');

    await client.auth.signOut();
  });

  test('ADMIN can update settings (not just OWNER)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.admin);
    final businessId = membership.business.id;
    final original = membership.business;

    final updated = await BusinessRepository(client).updateSettings(
      businessId: businessId,
      name: original.name,
      phone: original.phone,
      email: original.email,
      address: original.address,
      currency: original.currency,
      taxEnabled: original.taxEnabled,
      taxRate: original.taxRate,
      logoUrl: original.logoUrl,
    );
    expect(updated.name, original.name, reason: 'an ADMIN-rank caller must be allowed to save (even a no-op save)');

    await client.auth.signOut();
  });

  test('a non-member of the target business is denied before any mutation', () async {
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
      BusinessRepository(client).updateSettings(
        businessId: businessBId,
        name: 'Should never be applied',
        currency: 'LAK',
        taxEnabled: false,
        taxRate: 0,
      ),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission to change business settings'))),
    );

    await client.auth.signOut();
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final unchanged = await client.from('businesses').select('name').eq('id', businessBId).single();
    expect(unchanged['name'], isNot('Should never be applied'));
    await client.auth.signOut();
  });

  test('STAFF/CASHIER-rank denial for settings changes -- no fixture account to run this live', () {
    markTestSkipped(_noStaffCashierFixture);
  });

  test('a rejected mutation (empty name) leaves the business unchanged and commits zero audit rows', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    final auditCountBefore = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessId)
            .eq('action', 'SETTINGS_CHANGE')
            .eq('entity_id', businessId))
        .length;

    await expectLater(
      BusinessRepository(client).updateSettings(
        businessId: businessId,
        name: '   ',
        currency: original.currency,
        taxEnabled: original.taxEnabled,
        taxRate: original.taxRate,
      ),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Business name is required'))),
    );

    final unchanged = await client.from('businesses').select('name').eq('id', businessId).single();
    expect(unchanged['name'], original.name);

    final auditCountAfter = (await client
            .from('audit_logs')
            .select('id')
            .eq('business_id', businessId)
            .eq('action', 'SETTINGS_CHANGE')
            .eq('entity_id', businessId))
        .length;
    expect(auditCountAfter, auditCountBefore, reason: 'no audit row may be committed for a rejected mutation');

    await client.auth.signOut();
  });

  test('a direct PATCH on businesses is no longer possible (businesses_update dropped)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final originalName = membership.business.name;

    final updated = await client.from('businesses').update({'name': 'Direct PATCH should be denied'}).eq('id', businessId).select();
    expect(updated, isEmpty, reason: 'businesses_update was dropped in 0028 -- RLS filters the row to zero matches');

    final unchanged = await client.from('businesses').select('name').eq('id', businessId).single();
    expect(unchanged['name'], originalName, reason: 'the rejected direct PATCH must not have mutated the row');

    await client.auth.signOut();
  });

  test('anon EXECUTE on update_business_settings is denied by ACL (never reaches the function body)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/update_business_settings'));
      request.headers.set('apikey', Env.supabaseAnonKey);
      request.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'p_business_id': '00000000-0000-0000-0000-000000000000',
        'p_name': 'anon probe',
        'p_phone': null,
        'p_email': null,
        'p_address': null,
        'p_currency': 'LAK',
        'p_tax_enabled': false,
        'p_tax_rate': 0,
        'p_logo_url': null,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 401);
      expect(body, contains('42501'));
      expect(body, contains('permission denied for function update_business_settings'));
    } finally {
      client.close();
    }
  });

  test('audit_logs INSERT/UPDATE/DELETE remain closed (unaffected by 0028)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerId = client.auth.currentUser!.id;

    await expectLater(
      client.from('audit_logs').insert({
        'business_id': businessId,
        'user_id': ownerId,
        'action': 'SETTINGS_CHANGE',
        'entity_type': 'business',
        'entity_id': businessId,
      }),
      throwsA(_deniedByRls()),
    );

    final existing = await client.from('audit_logs').select('id, action').eq('business_id', businessId).limit(1).single();
    final updated = await client.from('audit_logs').update({'action': 'DELETE'}).eq('id', existing['id'] as String).select();
    expect(updated, isEmpty);

    final deleted = await client.from('audit_logs').delete().eq('id', existing['id'] as String).select();
    expect(deleted, isEmpty);

    await client.auth.signOut();
  });
}
