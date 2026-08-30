import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/business_role.dart';
import '../../auth/presentation/business_context_provider.dart';

/// No new repository here -- the Settings screen reads the current
/// business from the existing currentMembershipProvider (auth feature)
/// and saves via the existing businessRepositoryProvider's
/// updateSettings(), invalidating myMembershipsProvider on success so
/// every existing consumer of the business profile (sidebar header, cart
/// tax calc) picks up the change naturally. This provider is purely a UX
/// convenience (hide/disable the form for a role that would be rejected
/// anyway) -- never the actual security boundary, which is
/// update_business_settings' own has_role_at_least check
/// (0028_business_settings_rpc.sql).
final canEditBusinessSettingsProvider = Provider.autoDispose<bool>((ref) {
  final role = ref.watch(currentMembershipProvider)?.role;
  return role?.isAtLeast(BusinessRole.admin) ?? false;
});
