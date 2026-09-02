import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/appointment.dart';
import '../../../shared/models/appointment_item.dart';

/// All writes go through the SECURITY DEFINER RPCs in
/// supabase/migrations/0031_appointment_rpcs.sql -- appointments/
/// appointment_items have a SELECT-only RLS policy (see
/// 0030_appointments_schema.sql), exactly like business_members after F9-3,
/// so there is no direct insert/update path here to keep in sync with.
class AppointmentRepository {
  final SupabaseClient _client;

  AppointmentRepository(this._client);

  static const _selectColumns = '''
    *,
    customers(name),
    profiles!appointments_staff_id_fkey(full_name),
    appointment_items(*)
  ''';

  /// Appointments whose time range overlaps [rangeStart, rangeEnd).
  Future<List<Appointment>> listForRange({
    required String businessId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final rows = await _client
        .from('appointments')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .lt('start_at', rangeEnd.toIso8601String())
        .gt('end_at', rangeStart.toIso8601String())
        .order('start_at');
    return (rows as List)
        .map((r) => Appointment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The RPCs return only the bare `appointments` row (no joins); fetch the
  /// enriched version with customer/staff names and items for display.
  Future<Appointment> _fetchById(String businessId, String id) async {
    final row = await _client
        .from('appointments')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('id', id)
        .single();
    return Appointment.fromJson(row);
  }

  Future<Appointment> book({
    required String businessId,
    String? branchId,
    String? customerId,
    required String staffId,
    required DateTime startAt,
    required DateTime endAt,
    required List<AppointmentItem> items,
    String? notes,
  }) async {
    final row = await _client.rpc('book_appointment', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_customer_id': customerId,
      'p_staff_id': staffId,
      'p_start_at': startAt.toIso8601String(),
      'p_end_at': endAt.toIso8601String(),
      'p_items': items.map((i) => i.toBookingJson()).toList(),
      'p_notes': notes,
    }) as Map<String, dynamic>;
    return _fetchById(businessId, row['id'] as String);
  }

  Future<Appointment> setStatus({
    required String businessId,
    required String appointmentId,
    required String status,
    String? cancelReason,
  }) async {
    await _client.rpc('set_appointment_status', params: {
      'p_business_id': businessId,
      'p_appointment_id': appointmentId,
      'p_status': status,
      'p_cancel_reason': cancelReason,
    });
    return _fetchById(businessId, appointmentId);
  }

  Future<Appointment> reschedule({
    required String businessId,
    required String appointmentId,
    required String staffId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    await _client.rpc('reschedule_appointment', params: {
      'p_business_id': businessId,
      'p_appointment_id': appointmentId,
      'p_staff_id': staffId,
      'p_start_at': startAt.toIso8601String(),
      'p_end_at': endAt.toIso8601String(),
    });
    return _fetchById(businessId, appointmentId);
  }
}
