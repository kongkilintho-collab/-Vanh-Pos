// F1 regression coverage (see POS_IMPLEMENTATION_PLAN.md QA history):
// BusinessRepository.myMemberships() previously had no user_id filter and
// relied only on RLS's is_member(business_id) check, which scopes rows to
// *businesses the caller belongs to* — not to the caller's *own* rows in
// those businesses. That let an invited non-owner's dashboard resolve a
// co-member's (e.g. the OWNER's) row as if it were their own, via
// currentMembershipProvider's `.first` fallback.
//
// This is a LIVE test against the Supabase project configured via
// --dart-define-from-file=env.json, using two pre-existing QA fixture
// accounts created directly in the Supabase dashboard for this purpose
// (Auto Confirm User enabled, so no email confirmation is required):
//   - van@test.local   / admin123456@   — OWNER of one business ("A")
//   - admin@test.local / 123456@12      — OWNER of a second business, and
//     was invited into business "A" as ADMIN
//
// It skips itself (does not fail) when Supabase isn't configured, so a
// plain `flutter test` elsewhere stays green.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/business_repository_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/auth/presentation/auth_providers.dart';
import 'package:beauty_clinic_pos/features/auth/presentation/business_context_provider.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided — run with '
    '--dart-define-from-file=env.json against a project seeded with the '
    'QA fixture accounts (see file header).';

/// Supabase's edge/WAF layer intermittently rejects auth requests fired in
/// rapid succession (this suite signs in and out repeatedly across many
/// tests within a fraction of a second) with a spurious empty-body 400 —
/// confirmed unrelated to the credentials or the F1 fix, since an isolated
/// `dart run` hitting the same endpoint once always succeeds. A short
/// spacing plus one retry absorbs that without masking a real auth failure
/// (a genuine bad-credentials error is an AuthApiException with a real
/// body, not an empty-body AuthUnknownException, so it still surfaces).
Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Future<Set<String>> _rawOwnMembershipIds(SupabaseClient client, String userId) async {
  final rows = await client
      .from('business_members')
      .select('id')
      .eq('user_id', userId)
      .eq('active', true);
  return (rows as List).map((r) => r['id'] as String).toSet();
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    // `flutter test` runs in a plain Dart VM with no real platform
    // channels; mock the shared_preferences channel supabase_flutter's
    // internal storage relies on so Supabase.initialize doesn't throw
    // MissingPluginException here (this test doesn't exercise session
    // persistence across restarts, so an in-memory mock is sufficient).
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  group('BusinessRepository.myMemberships() — F1 regression', () {
    test('User A receives only User A\'s own membership rows', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final userId = client.auth.currentUser!.id;

      final expectedIds = await _rawOwnMembershipIds(client, userId);
      final actual = await BusinessRepository(client).myMemberships();

      expect(actual, isNotEmpty);
      expect(
        actual.map((m) => m.id).toSet(),
        expectedIds,
        reason: 'myMemberships() must return exactly the caller\'s own '
            'business_members rows — no more, no less',
      );

      await client.auth.signOut();
    });

    test('User B receives only User B\'s own rows, never User A\'s OWNER row', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // Learn User A's own row ids first (ground truth for the
      // "never leaks a foreign row" assertion below), then sign out.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final ownerARowIds = await _rawOwnMembershipIds(client, client.auth.currentUser!.id);
      await client.auth.signOut();

      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final userBId = client.auth.currentUser!.id;
      final expectedIds = await _rawOwnMembershipIds(client, userBId);
      final actual = await BusinessRepository(client).myMemberships();

      expect(actual, isNotEmpty);
      expect(actual.map((m) => m.id).toSet(), expectedIds);

      for (final row in actual) {
        expect(
          ownerARowIds.contains(row.id),
          isFalse,
          reason: 'myMemberships() for User B returned one of User A\'s '
              'own rows (${row.id}) — this was exactly the F1 defect',
        );
      }

      await client.auth.signOut();
    });

    test(
      'currentMembershipProvider resolves the authenticated user\'s actual '
      'role, never a co-member\'s',
      () async {
        if (!_canRun) {
          markTestSkipped(_skipReason);
          return;
        }
        final client = Supabase.instance.client;

        await _signIn(client, _ownerBEmail, _ownerBPassword);
        final memberships = await BusinessRepository(client).myMemberships();
        // User B genuinely holds OWNER (their own business) and ADMIN
        // (invited into User A's business) — never OWNER of User A's
        // business, which was the specific F1 failure mode.
        expect(memberships.map((m) => m.role), containsAll([BusinessRole.owner, BusinessRole.admin]));

        final container = ProviderContainer(overrides: [
          myMembershipsProvider.overrideWith((ref) => Future.value(memberships)),
        ]);
        addTearDown(container.dispose);

        // myMembershipsProvider is a FutureProvider: even an already-
        // completed override future needs one microtask turn before its
        // AsyncValue settles from loading to data. Await it explicitly so
        // the read below doesn't race an empty/loading state.
        await container.read(myMembershipsProvider.future);
        final resolved = container.read(currentMembershipProvider);
        expect(resolved, isNotNull);
        expect(
          memberships.map((m) => m.id),
          contains(resolved!.id),
          reason: 'currentMembershipProvider resolved a membership that '
              'was not in the (already-verified-own) memberships list',
        );

        await client.auth.signOut();
      },
    );
  });

  group('SEC-CRITICAL escalation guards (pre-existing protections — must remain intact)', () {
    test('ADMIN cannot self-escalate to OWNER via raw UPDATE', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final userBId = client.auth.currentUser!.id;

      final memberships = await BusinessRepository(client).myMemberships();
      final adminRow = memberships.firstWhere((m) => m.role == BusinessRole.admin);

      // The USING clause lets this row through (an ADMIN may touch their
      // own non-OWNER row), so the update targets a real row — it's the
      // WITH CHECK clause that then rejects the new role, which Postgres
      // surfaces as an explicit RLS violation rather than a silent 0-row
      // update (contrast with the "demote the real OWNER" case below,
      // which the USING clause blocks before any row is matched).
      await expectLater(
        client
            .from('business_members')
            .update({'role': 'OWNER'})
            .eq('business_id', adminRow.business.id)
            .eq('user_id', userBId)
            .select(),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
        reason: 'RLS must block ADMIN self-escalation to OWNER',
      );

      final recheck = await BusinessRepository(client).myMemberships();
      final stillAdmin = recheck.firstWhere((m) => m.business.id == adminRow.business.id);
      expect(stillAdmin.role, BusinessRole.admin);

      await client.auth.signOut();
    });

    test('ADMIN cannot demote the real OWNER', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);

      final memberships = await BusinessRepository(client).myMemberships();
      final adminRow = memberships.firstWhere((m) => m.role == BusinessRole.admin);

      final ownerRows = await client
          .from('business_members')
          .select('id, user_id, role')
          .eq('business_id', adminRow.business.id)
          .eq('role', 'OWNER');
      expect(ownerRows, isNotEmpty);
      final ownerUserId = (ownerRows as List).first['user_id'] as String;

      final result = await client
          .from('business_members')
          .update({'role': 'STAFF'})
          .eq('business_id', adminRow.business.id)
          .eq('user_id', ownerUserId)
          .select();
      expect(result, isEmpty, reason: 'RLS must block a non-owner demoting the real OWNER');

      await client.auth.signOut();
    });

    test('sole OWNER cannot demote themselves', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final userAId = client.auth.currentUser!.id;

      final memberships = await BusinessRepository(client).myMemberships();
      final ownRow = memberships.firstWhere((m) => m.role == BusinessRole.owner);

      await expectLater(
        client
            .from('business_members')
            .update({'role': 'ADMIN'})
            .eq('business_id', ownRow.business.id)
            .eq('user_id', userAId)
            .select(),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('last owner'),
          ),
        ),
        reason: 'the last-owner guard trigger must block a sole OWNER demoting themselves',
      );

      await client.auth.signOut();
    });
  });
}
