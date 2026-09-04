import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/follow_up.dart';
import '../../../shared/models/follow_up_status.dart';

/// Which server-side WHERE clause listForBusiness applies -- each filter
/// is expressed as a database query, never as a client-side filter over
/// an unscoped fetch (e.g. "Overdue" never downloads completed/cancelled
/// rows just to discard them in the widget tree).
enum FollowUpListFilter { dueToday, overdue, upcoming, completed }

DateTime _startOfLocalDay(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// All writes go through the SECURITY DEFINER RPCs in
/// supabase/migrations/0049_follow_ups_and_line_oa.sql -- follow_ups has a
/// SELECT + narrative-only-UPDATE RLS policy (see that migration), exactly
/// like consultations/treatment_history, so there is no direct insert path
/// here to keep in sync with.
class FollowUpRepository {
  final SupabaseClient _client;

  FollowUpRepository(this._client);

  static const _selectColumns = '*, customers(name)';

  Future<List<FollowUp>> listForCustomer(String businessId, String customerId) async {
    final rows = await _client
        .from('follow_ups')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('due_date', ascending: false);
    return (rows as List).map((r) => FollowUp.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Business-wide list for the Follow-up List screen and the Dashboard
  /// "Due Today"/"Overdue" tiles. Day boundaries are computed from the
  /// device's local calendar day, converted to UTC only when building the
  /// query -- never a naive string comparison against due_date.
  Future<List<FollowUp>> listForBusiness(String businessId, FollowUpListFilter filter) async {
    final todayStart = _startOfLocalDay(DateTime.now());
    final todayEnd = todayStart.add(const Duration(days: 1));

    var query = _client.from('follow_ups').select(_selectColumns).eq('business_id', businessId);

    switch (filter) {
      case FollowUpListFilter.dueToday:
        query = query
            .eq('status', FollowUpStatus.pending.dbValue)
            .gte('due_date', todayStart.toUtc().toIso8601String())
            .lt('due_date', todayEnd.toUtc().toIso8601String());
      case FollowUpListFilter.overdue:
        query = query
            .eq('status', FollowUpStatus.pending.dbValue)
            .lt('due_date', todayStart.toUtc().toIso8601String());
      case FollowUpListFilter.upcoming:
        query = query
            .eq('status', FollowUpStatus.pending.dbValue)
            .gte('due_date', todayEnd.toUtc().toIso8601String());
      case FollowUpListFilter.completed:
        query = query.eq('status', FollowUpStatus.completed.dbValue);
    }

    final ascending = filter != FollowUpListFilter.completed;
    final rows = await query.order('due_date', ascending: ascending);
    return (rows as List).map((r) => FollowUp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<FollowUp> _fetchById(String businessId, String id) async {
    final row = await _client
        .from('follow_ups')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('id', id)
        .single();
    return FollowUp.fromJson(row);
  }

  Future<FollowUp> create({
    required String businessId,
    required String customerId,
    required String assignedStaffId,
    required DateTime dueDate,
    String? followUpNotes,
    String? consultationId,
    String? treatmentHistoryId,
    String? appointmentId,
  }) async {
    final row = await _client.rpc('create_follow_up', params: {
      'p_business_id': businessId,
      'p_customer_id': customerId,
      'p_assigned_staff_id': assignedStaffId,
      'p_due_date': dueDate.toUtc().toIso8601String(),
      'p_follow_up_notes': followUpNotes,
      'p_consultation_id': consultationId,
      'p_treatment_history_id': treatmentHistoryId,
      'p_appointment_id': appointmentId,
    }) as Map<String, dynamic>;
    return _fetchById(businessId, row['id'] as String);
  }

  Future<FollowUp> reschedule({
    required String businessId,
    required String followUpId,
    required DateTime dueDate,
    required String assignedStaffId,
  }) async {
    await _client.rpc('reschedule_follow_up', params: {
      'p_business_id': businessId,
      'p_follow_up_id': followUpId,
      'p_due_date': dueDate.toUtc().toIso8601String(),
      'p_assigned_staff_id': assignedStaffId,
    });
    return _fetchById(businessId, followUpId);
  }

  Future<FollowUp> setStatus({
    required String businessId,
    required String followUpId,
    required FollowUpStatus status,
  }) async {
    await _client.rpc('set_follow_up_status', params: {
      'p_business_id': businessId,
      'p_follow_up_id': followUpId,
      'p_status': status.dbValue,
    });
    return _fetchById(businessId, followUpId);
  }

  Future<void> updateNotes({required String id, String? followUpNotes}) async {
    await _client.from('follow_ups').update({'follow_up_notes': followUpNotes}).eq('id', id);
  }

  // --- LINE linking (Phase 6) ---
  //
  // Deliberately never selects line_user_id -- only linked_at -- so the
  // raw LINE identifier never reaches the client, not even as an unused
  // model field. Reading customer_line_accounts is allowed by RLS
  // (is_member), but this repository never asks for the one column that
  // must stay server-only in spirit as well as in the write path.

  Future<DateTime?> getLineLinkedAt(String businessId, String customerId) async {
    final row = await _client
        .from('customer_line_accounts')
        .select('linked_at')
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .maybeSingle();
    if (row == null) return null;
    return DateTime.parse(row['linked_at'] as String);
  }

  /// Returns the short-lived linking code for staff to relay to the
  /// customer (e.g. "text this code to our LINE account"). The resulting
  /// line_user_id is only ever written by the line-webhook Edge Function,
  /// never by this app.
  Future<String> createLineLinkCode(String businessId, String customerId) async {
    final row = await _client.rpc('create_line_link_code', params: {
      'p_business_id': businessId,
      'p_customer_id': customerId,
    }) as Map<String, dynamic>;
    return row['code'] as String;
  }

  Future<void> unlinkLineAccount(String businessId, String customerId) async {
    await _client.rpc('unlink_customer_line_account', params: {
      'p_business_id': businessId,
      'p_customer_id': customerId,
    });
  }
}
