// Live regression coverage for Day 3 P0's find_invitable_user_id RPC (see
// supabase/migrations/0018_staff_invite_lookup.sql) -- the email-to-user_id
// lookup that unblocks Staff -> Invite by Email, since profiles carries no
// email column and invite_business_member() needs a user_id.
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/staff_invite_lookup_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
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
    '0018_staff_invite_lookup.sql applied and seeded with the QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

/// Calls the RPC with a positional-equivalent named-params map, matching
/// exactly how the (not-yet-written) StaffRepository will call it.
Future<dynamic> _lookup(SupabaseClient client, String businessId, String email) {
  return client.rpc('find_invitable_user_id', params: {
    'p_business_id': businessId,
    'p_email': email,
  });
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('A: authorized ADMIN looking up a real email gets the matching user_id', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    // User B is ADMIN of Business A (established in earlier QA sessions).
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final memberships = await BusinessRepository(client).myMemberships();
    final businessAId = memberships.firstWhere((m) => m.role == BusinessRole.admin).business.id;

    final result = await _lookup(client, businessAId, _ownerAEmail);
    expect(result, isNotNull);
    expect(result, isA<String>());

    await client.auth.signOut();
  });

  test('B: a real member below ADMIN rank is rejected', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;

    // Fixture setup: User B (OWNER of Business B) invites User A into
    // Business B as CASHIER -- a real, low-rank membership to test against
    // (idempotent: invite_business_member upserts the role every run).
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final userAId = client.auth.currentUser!.id;
    await client.auth.signOut();

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessBId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    await client.rpc('invite_business_member', params: {
      'p_business_id': businessBId,
      'p_user_id': userAId,
      'p_role': 'CASHIER',
    });
    await client.auth.signOut();

    // User A, now a real CASHIER of Business B, tries the lookup there.
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    await expectLater(
      _lookup(client, businessBId, _ownerBEmail),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Insufficient permission'),
      )),
    );

    await client.auth.signOut();
  });

  test('C: an unauthenticated (anon) caller is rejected', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    // Ensure no session is active.
    await client.auth.signOut();

    // Use a syntactically valid but arbitrary business_id -- the rejection
    // must come from the missing auth context, not a business lookup.
    final anyBusinessId = _uuid.v4();

    // Since 0019 (revoke execute ... from anon), an anon caller is stopped
    // at the Postgres privilege layer before the function body ever runs
    // -- so this is Postgres's own "permission denied" error, not the
    // function's internal "Insufficient permission..." message (which an
    // *authenticated* but under-privileged caller gets instead -- see
    // test B). Getting this exact error is the P0 fix working correctly.
    await expectLater(
      _lookup(client, anyBusinessId, _ownerAEmail),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('permission denied for function find_invitable_user_id'),
      )),
    );
  });

  test('D: an unknown email returns null, not an error', () async {
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

    final result = await _lookup(client, businessAId, 'definitely-nobody-${_uuid.v4()}@nowhere.invalid');
    expect(result, isNull);

    await client.auth.signOut();
  });

  test('E: a caller with zero membership in the target business is rejected '
      '(business-scoped, not "ADMIN of anything")', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);

    // A syntactically valid business_id that does not correspond to any
    // membership this caller has -- proves the check is scoped to the
    // specific business_id argument, not "is this caller an ADMIN of
    // *some* business".
    final unrelatedBusinessId = _uuid.v4();

    await expectLater(
      _lookup(client, unrelatedBusinessId, _ownerBEmail),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Insufficient permission'),
      )),
    );

    await client.auth.signOut();
  });

  test('F: end-to-end lookup-then-invite works, and invite_business_member '
      'escalation guards are unaffected', () async {
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

    // Real usage chain: resolve email -> user_id, then invite with it.
    final resolvedId = await _lookup(client, businessAId, _ownerAEmail);
    expect(resolvedId, isNotNull);

    // User A is already OWNER of Business A -- re-inviting them as CASHIER
    // must still be blocked by invite_business_member's own escalation
    // rules (a non-owner ADMIN cannot touch an OWNER's row), proving this
    // new lookup function introduces no bypass of that protection.
    await expectLater(
      client.rpc('invite_business_member', params: {
        'p_business_id': businessAId,
        'p_user_id': resolvedId,
        'p_role': 'CASHIER',
      }),
      throwsA(isA<PostgrestException>()),
    );

    await client.auth.signOut();
  });

  test('G: SQL-metacharacter input is treated as a literal, inert string', () async {
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

    const malicious = "'; drop table profiles; --";
    final result = await _lookup(client, businessAId, malicious);
    expect(result, isNull, reason: 'a malformed/malicious string must just fail to match, not error or execute');

    // Prove nothing was actually dropped: a normal, known-good lookup
    // still works immediately after.
    final sane = await _lookup(client, businessAId, _ownerAEmail);
    expect(sane, isNotNull);

    await client.auth.signOut();
  });
}
