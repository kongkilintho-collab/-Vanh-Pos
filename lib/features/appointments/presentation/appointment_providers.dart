import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/appointment.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/appointment_repository.dart';

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(supabaseClientProvider));
});

class AppointmentRange {
  final DateTime start;
  final DateTime end;

  const AppointmentRange(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is AppointmentRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final appointmentsForRangeProvider = FutureProvider.autoDispose
    .family<List<Appointment>, AppointmentRange>((ref, range) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(appointmentRepositoryProvider).listForRange(
        businessId: membership.business.id,
        rangeStart: range.start,
        rangeEnd: range.end,
      );
});
