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
    final hydrated = await _hydratePackageItems((rows as List).cast<Map<String, dynamic>>());
    return hydrated.map(Appointment.fromJson).toList();
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
    final hydrated = await _hydratePackageItems([row]);
    return Appointment.fromJson(hydrated.single);
  }

  /// appointment_items(*) deliberately does NOT embed customer_package_items
  /// via a PostgREST relationship -- that embed would make every appointment
  /// read fail outright (PGRST200) on any project where the Phase 2
  /// migrations aren't live yet, since Phase 1's appointments feature must
  /// keep working independently of Phase 2. Instead this resolves the
  /// handful of linked customer_package_items with one extra query, and
  /// only when at least one item actually carries a
  /// customer_package_item_id -- which is null on every row until a Phase 2
  /// migration + booking has actually happened, so this is a no-op (no
  /// extra query at all) for any appointment with no package link.
  Future<List<Map<String, dynamic>>> _hydratePackageItems(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = <String>{};
    for (final row in rows) {
      final items = (row['appointment_items'] as List<dynamic>?) ?? const [];
      for (final item in items) {
        final id = (item as Map<String, dynamic>)['customer_package_item_id'] as String?;
        if (id != null) ids.add(id);
      }
    }
    if (ids.isEmpty) return rows;

    final cpiRows = await _client
        .from('customer_package_items')
        .select('id, name_snapshot, total_sessions, used_sessions')
        .inFilter('id', ids.toList());
    final byId = {
      for (final r in (cpiRows as List).cast<Map<String, dynamic>>()) r['id'] as String: r,
    };

    for (final row in rows) {
      final items = (row['appointment_items'] as List<dynamic>?) ?? const [];
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final id = m['customer_package_item_id'] as String?;
        if (id != null && byId.containsKey(id)) {
          m['customer_package_items'] = byId[id];
        }
      }
    }
    return rows;
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
