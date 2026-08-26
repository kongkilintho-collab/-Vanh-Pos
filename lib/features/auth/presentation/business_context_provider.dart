import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/business_membership.dart';
import 'auth_providers.dart';

/// Lets a user with multiple memberships pick which business they're
/// operating in. Null means "no explicit choice yet" — the UI falls back
/// to the first membership in [currentMembershipProvider].
final selectedBusinessIdProvider = StateProvider<String?>((ref) => null);

/// The membership the app should currently act as, or null while loading
/// or when the user has no business yet.
final currentMembershipProvider = Provider<BusinessMembership?>((ref) {
  final memberships = ref.watch(myMembershipsProvider).valueOrNull ?? const [];
  if (memberships.isEmpty) return null;

  final selectedId = ref.watch(selectedBusinessIdProvider);
  if (selectedId != null) {
    for (final m in memberships) {
      if (m.business.id == selectedId) return m;
    }
  }
  return memberships.first;
});
