import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import 'sheet_parts.dart';

/// §ANALYTICS.CUSTOM_SHEET — the Custom date-range sheet.
class AnalyticsCustomDatesSheet extends StatefulWidget {
  const AnalyticsCustomDatesSheet({
    super.key,
    required this.palette,
    required this.from,
    required this.to,
    required this.today,
    required this.firstDate,
  });

  final AppPalette palette;
  final DateTime from;
  final DateTime to;
  final DateTime today;
  final DateTime firstDate;

  @override
  State<AnalyticsCustomDatesSheet> createState() => _CustomDatesSheetState();
}

class _CustomDatesSheetState extends State<AnalyticsCustomDatesSheet> {
  late DateTime _from = widget.from;
  late DateTime _to = widget.to;

  /// F4: the range can't be backwards. To can't start before From; From
  /// keeps today as its upper bound, and moving it past To drags To along.
  Future<void> _pick(bool from) async {
    final bounds = customRangePickerBounds(
      from: _from,
      today: widget.today,
      firstDate: widget.firstDate,
      pickingFrom: from,
    );
    final initial = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(bounds.$1) ? bounds.$1 : (initial.isAfter(bounds.$2) ? bounds.$2 : initial),
      firstDate: bounds.$1,
      lastDate: bounds.$2,
      builder: (ctx, child) => Theme(data: analyticsPickerTheme(widget.palette), child: child!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    Widget field(String label, Key key, DateTime value, bool from) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          analyticsFieldLabel(p, label),
          const SizedBox(height: 4),
          InkWell(
            key: key,
            onTap: () => _pick(from),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: analyticsFieldBox(p),
              child: Text(analyticsFmtFieldDate(value), style: TextStyle(fontSize: 13, color: p.ink)),
            ),
          ),
        ],
      ),
    );
    return BottomSheetShell(
      palette: p,
      children: [
        Text(
          'Custom dates',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
        ),
        Row(
          children: [
            field('From', const Key('analyticsCustomFrom'), _from, true),
            const SizedBox(width: 10),
            field('To', const Key('analyticsCustomTo'), _to, false),
          ],
        ),
        AnalyticsSheetActions(
          palette: p,
          cancelKey: const Key('analyticsCustomCancel'),
          primaryKey: const Key('analyticsCustomShow'),
          primaryLabel: 'Show',
          onPrimary: () => Navigator.of(context).pop(AnalyticsPeriod.custom(_from, _to, today: widget.today)),
        ),
      ],
    );
  }
}
