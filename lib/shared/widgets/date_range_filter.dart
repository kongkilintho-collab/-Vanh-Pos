import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

enum DateRangePreset { today, thisWeek, thisMonth, custom }

/// An inclusive [from, to] range with a preset label, used to filter
/// reports. `from` is always midnight of its day; `to` is always the last
/// millisecond of its day, so `gte`/`lte` range queries include both
/// endpoint days in full.
class DateRangeSelection {
  final DateRangePreset preset;
  final DateTime from;
  final DateTime to;

  const DateRangeSelection({
    required this.preset,
    required this.from,
    required this.to,
  });

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  factory DateRangeSelection.today() {
    final today = _startOfDay(DateTime.now());
    return DateRangeSelection(
      preset: DateRangePreset.today,
      from: today,
      to: _endOfDay(today),
    );
  }

  factory DateRangeSelection.thisWeek() {
    final today = _startOfDay(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    return DateRangeSelection(
      preset: DateRangePreset.thisWeek,
      from: weekStart,
      to: _endOfDay(today),
    );
  }

  factory DateRangeSelection.thisMonth() {
    final today = _startOfDay(DateTime.now());
    final monthStart = DateTime(today.year, today.month, 1);
    return DateRangeSelection(
      preset: DateRangePreset.thisMonth,
      from: monthStart,
      to: _endOfDay(today),
    );
  }

  factory DateRangeSelection.custom(DateTime from, DateTime to) {
    return DateRangeSelection(
      preset: DateRangePreset.custom,
      from: _startOfDay(from),
      to: _endOfDay(to),
    );
  }
}

/// A segmented Today/This week/This month/Custom control. Purely
/// presentational -- the caller owns the [DateRangeSelection] state
/// (typically via a Riverpod provider) and re-renders this with the new
/// `selection` on [onChanged].
class DateRangeFilterBar extends StatelessWidget {
  final DateRangeSelection selection;
  final ValueChanged<DateRangeSelection> onChanged;

  const DateRangeFilterBar({
    super.key,
    required this.selection,
    required this.onChanged,
  });

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(start: selection.from, end: selection.to),
    );
    if (picked != null) {
      onChanged(DateRangeSelection.custom(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DateRangePreset>(
      segments: [
        ButtonSegment(
          value: DateRangePreset.today,
          label: Text(context.l10n.dateRangeToday),
        ),
        ButtonSegment(
          value: DateRangePreset.thisWeek,
          label: Text(context.l10n.dateRangeThisWeek),
        ),
        ButtonSegment(
          value: DateRangePreset.thisMonth,
          label: Text(context.l10n.dateRangeThisMonth),
        ),
        ButtonSegment(
          value: DateRangePreset.custom,
          label: Text(context.l10n.dateRangeCustom),
        ),
      ],
      selected: {selection.preset},
      onSelectionChanged: (s) {
        final preset = s.first;
        switch (preset) {
          case DateRangePreset.today:
            onChanged(DateRangeSelection.today());
          case DateRangePreset.thisWeek:
            onChanged(DateRangeSelection.thisWeek());
          case DateRangePreset.thisMonth:
            onChanged(DateRangeSelection.thisMonth());
          case DateRangePreset.custom:
            _pickCustomRange(context);
        }
      },
    );
  }
}
