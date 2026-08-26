import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../data/auth_repository.dart';
import '../data/business_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return BusinessRepository(ref.watch(supabaseClientProvider));
});

/// Emits on every sign-in / sign-out / token refresh.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// The current session's user, or null when signed out. Derives from
/// [authStateChangesProvider] so it updates reactively.
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider).valueOrNull;
  return authState?.session?.user ?? ref.watch(authRepositoryProvider).currentUser;
});

/// The signed-in user's business memberships. Re-fetches whenever the auth
/// state changes (sign in/out) so it never leaks a previous user's data.
final myMembershipsProvider = FutureProvider((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(businessRepositoryProvider).myMemberships();
});
