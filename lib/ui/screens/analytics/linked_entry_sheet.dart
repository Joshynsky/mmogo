import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/ksh_amount.dart';
import '../../../domain/format/money.dart';
import '../../copy/withdrawal_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/ksh_input_formatter.dart';
import '../../widgets/withdrawal_use_block.dart';
import '../../widgets/withdrawal_use_create.dart';
import 'edit_sheet.dart' show AnalyticsDeleteRequest;
import 'sheet_parts.dart';

/// What the linked-entry sheet gives back when Save (or "Add another entry") is tapped.
class LinkedEntryResult {
  const LinkedEntryResult({required this.amountCents, required this.categoryId, this.addAnother = false});
  final int amountCents;
  final int categoryId;

  /// Save this entry, then open a new one for what is still left.
  final bool addAnother;
}

/// §ANALYTICS.LINKED_ENTRY_SHEET (0.2.1) — edit (or start) a Cash entry that came from a withdrawal.
/// Amount stepper (Ksh 100 steps, typed too) capped at [maxCents] = what the withdrawal has left
/// counting this entry's own amount; the rest stays cash and the words say so. Category chips from
/// the Cash picker. Date and time are the withdrawal's and cannot change. Delete is offered for a
/// saved entry ([AnalyticsDeleteRequest]).
class LinkedEntrySheet extends StatefulWidget {
  const LinkedEntrySheet({
    super.key,
    required this.db,
    required this.palette,
    required this.withdrawalCents,
    required this.occurredAt,
    required this.maxCents,
    required this.isNew,
    this.categoryId,
    this.categoryName,
    this.amountCents,
  });

  final Database db;
  final AppPalette palette;
  final int withdrawalCents;
  final DateTime occurredAt;
  final int maxCents;
  final bool isNew;
  final int? categoryId;
  final String? categoryName;
  final int? amountCents;

  @override
  State<LinkedEntrySheet> createState() => _LinkedEntrySheetState();
}

class _LinkedEntrySheetState extends State<LinkedEntrySheet> {
  late final _amount = TextEditingController(text: _fmt(widget.amountCents ?? widget.maxCents));
  List<WdChoice> _choices = const [];
  int? _categoryId;
  String? _categoryName;

  static String _fmt(int cents) => (cents / 100).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _categoryName = widget.categoryName;
    unawaited(
      loadWithdrawalUseChoices(widget.db).then((cats) {
        if (!mounted) return;
        setState(() => _choices = _keepOwnCategory(cats));
      }),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The entry's own category stays a chip even when it is not in the Cash list (made before it existed).
  List<WdChoice> _keepOwnCategory(List<WdChoice> cats) {
    final own = widget.categoryId;
    final ownName = widget.categoryName;
    return [
      ...cats,
      if (own != null && ownName != null && !cats.any((c) => c.id == own)) WdChoice(own, ownName),
    ];
  }

  int? get _cents => parseKshCents(_amount.text);
  bool get _amountOk => _cents != null && _cents! <= widget.maxCents;
  bool get _canSave => _amountOk && _categoryId != null;
  String get _dayText => '${weekdayShort(widget.occurredAt)}, ${fmtDayMonth(widget.occurredAt)}';

  void _step(int deltaCents) {
    final next = ((_cents ?? 0) + deltaCents).clamp(100, widget.maxCents);
    setState(() => _amount.text = _fmt(next));
  }

  void _done({required bool addAnother}) {
    if (!_canSave) return;
    Navigator.of(context).pop(LinkedEntryResult(amountCents: _cents!, categoryId: _categoryId!, addAnother: addAnother));
  }

  Widget _round(Key key, IconData icon, String label, bool on, VoidCallback tap) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        key: key,
        onTap: on ? tap : null,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.track, border: Border.all(color: p.line, width: 1.5)),
              child: Icon(icon, size: 16, color: on ? p.ink : p.mutedInk),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final cents = _cents ?? 0;
    final still = widget.maxCents - cents;
    final canAdd = _canSave && still > 0;
    return BottomSheetShell(
      palette: p,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _categoryName == null ? 'Cash entry' : wdCashTitle(_categoryName!),
                      key: const Key('linkedEntryTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: p.sun.withValues(alpha: 0.18), borderRadius: const BorderRadius.all(Radius.circular(8))),
                    child: Text(kWdFromWithdrawalTag, key: const Key('linkedEntryTag'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.sun)),
                  ),
                ],
              ),
            ),
            if (!widget.isNew)
              TextButton.icon(
                key: const Key('linkedEntryDelete'),
                onPressed: () => Navigator.of(context).pop(const AnalyticsDeleteRequest()),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: p.diffUp),
                label: Text('Delete', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.diffUp)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ],
        ),
        Text('Cash · ${widget.isNew ? kWdNewEntry : kWdSavedEntry}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mutedInk)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(10))),
          child: Text(
            wdEntryFromLine(widget.withdrawalCents, _dayText),
            key: const Key('linkedEntryFrom'),
            style: TextStyle(fontSize: 11.5, height: 1.4, color: p.mutedInk),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            analyticsFieldLabel(p, 'Amount (Ksh)'),
            const SizedBox(height: 4),
            Row(
              children: [
                _round(const Key('linkedEntryLess'), Icons.remove_rounded, 'Less', cents > 100, () => _step(-10000)),
                Expanded(
                  child: TextField(
                    key: const Key('linkedEntryAmount'),
                    controller: _amount,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [KshInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 13, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: p.background,
                      errorText: _amount.text.trim().isNotEmpty && !_amountOk
                          ? (_cents == null ? kshAmountHelp : 'Up to ${kshTrim(widget.maxCents)} fits here.')
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: p.line, width: 1.5),
                      ),
                    ),
                  ),
                ),
                _round(const Key('linkedEntryMore'), Icons.add_rounded, 'More', cents < widget.maxCents, () => _step(10000)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _amountOk
                  ? wdEntryRestWords(still, widget.maxCents)
                  : 'You can enter up to ${kshTrim(widget.maxCents)} here (what is left of the withdrawal).',
              key: const Key('linkedEntryWords'),
              style: TextStyle(fontSize: 11, height: 1.45, color: p.softInk),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            analyticsFieldLabel(p, 'Date & time'),
            const SizedBox(height: 4),
            Text(kWdEntrySameDate, style: TextStyle(fontSize: 11, color: p.mutedInk)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            analyticsFieldLabel(p, 'Category'),
            WithdrawalUseBlock(
              palette: p,
              choices: _choices,
              selectedId: _categoryId,
              showQuestion: false,
              showCashOnly: false,
              onCreate: (name) async {
                final r = await createWithdrawalUseCategory(widget.db, name);
                if (r.choices != null && mounted) setState(() => _choices = _keepOwnCategory(r.choices!));
                return r;
              },
              sentence: '',
              onChanged: (id) => setState(() {
                _categoryId = id;
                _categoryName = _choices.where((c) => c.id == id).map((c) => c.name).firstOrNull;
              }),
            ),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('linkedEntryAddAnother'),
          onPressed: canAdd ? () => _done(addAnother: true) : null,
          icon: Icon(Icons.add_rounded, size: 15, color: canAdd ? p.primary : p.mutedInk),
          label: Text(
            canAdd ? kWdAddAnother : kWdNothingLeft,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: canAdd ? p.primary : p.mutedInk),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
            side: BorderSide(color: p.mutedInk, width: 1.3),
          ),
        ),
        AnalyticsSheetActions(
          palette: p,
          cancelKey: const Key('linkedEntryCancel'),
          primaryKey: const Key('linkedEntrySave'),
          primaryLabel: 'Save',
          onPrimary: _canSave ? () => _done(addAnother: false) : null,
        ),
      ],
    );
  }
}
