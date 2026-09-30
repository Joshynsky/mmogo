import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/classification_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/source_types.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/flat_classification_picker.dart';
import '../../widgets/mpesa_classification_picker.dart';
import 'format.dart';
import 'sheet_parts.dart';

/// §ANALYTICS.EDIT_SHEET — the edit-transaction form, its result types and classification sub-sheet.
/// The edit form's "Delete" choice (handled by the screen, like the swipe).
class AnalyticsDeleteRequest {
  const AnalyticsDeleteRequest();
}

/// T13's edit form result: exactly the field set `TransactionDao.update`
/// accepts.
class AnalyticsEditResult {
  const AnalyticsEditResult({
    required this.amountCents,
    required this.transactionOccurredAt,
    required this.classificationId,
    this.counterpartyLabel,
    this.counterpartyPhone,
    this.paybillAccountNumber,
    this.transactionCostCents,
  });

  final int amountCents;
  final int transactionOccurredAt;
  final int classificationId;
  final String? counterpartyLabel;
  final String? counterpartyPhone;
  final String? paybillAccountNumber;
  final int? transactionCostCents;
}

String _fmtEditDateTime(DateTime d, DateTime now) {
  final time = analyticsHhmm(d);
  if (sameDay(d, now)) return 'Today, $time';
  return '${weekdayShort(d)}, ${fmtDayMonth(d)} ${d.year} · $time';
}

/// T13's edit form, restyled in Ocean & Sun (T21) — the same field set and
/// the same DAO call: Amount + Date/time + Classification for every type,
/// plus (non-Cash) Receiver/Business/Merchant name, (Send Money) Phone,
/// (Paybill) Account number and Transaction cost. No Code, Type or
/// capture toggle. Classification re-pick uses the real Add-flow pickers,
/// locked to the row's own type (the flat list for Cash). New in T21: a
/// Delete action (PM decision, 2026-09-25).
class AnalyticsEditSheet extends StatefulWidget {
  const AnalyticsEditSheet({super.key, required this.db, required this.tx, required this.palette});

  final Database db;
  final AnalyticsTransactionRow tx;
  final AppPalette palette;

  @override
  State<AnalyticsEditSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<AnalyticsEditSheet> {
  late final _amountController = TextEditingController(text: (widget.tx.amountCents / 100).toStringAsFixed(2));
  late final _labelController = TextEditingController(text: widget.tx.counterpartyLabel ?? '');
  late final _phoneController = TextEditingController(text: widget.tx.counterpartyPhone ?? '');
  late final _accountController = TextEditingController(text: widget.tx.paybillAccountNumber ?? '');
  late final _costController = TextEditingController(
    text: widget.tx.transactionCostCents == null ? '' : (widget.tx.transactionCostCents! / 100).toStringAsFixed(2),
  );

  late DateTime _occurredAt = widget.tx.occurredAt;
  late int _classificationId = widget.tx.classificationId;
  late String _classificationName = widget.tx.classificationName;

  bool get _isCash => widget.tx.sourceType == 'CASH';

  @override
  void dispose() {
    _amountController.dispose();
    _labelController.dispose();
    _phoneController.dispose();
    _accountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  int? _parsedAmountCents() {
    final value = double.tryParse(_amountController.text.trim());
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(data: analyticsPickerTheme(widget.palette), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
      builder: (ctx, child) => Theme(data: analyticsPickerTheme(widget.palette), child: child!),
    );
    if (time == null || !mounted) return;
    setState(() => _occurredAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _openClassificationPicker() async {
    final selected = await showModalBottomSheet<ClassificationItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The sheet and the Add-flow pickers inside it follow the app's palette
      // (dark when the app is dark).
      builder: (ctx) => Theme(
        data: analyticsPickerTheme(widget.palette),
        child: _EditClassificationPickerSheet(db: widget.db, sourceType: widget.tx.sourceType, palette: widget.palette),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _classificationId = selected.id;
        _classificationName = selected.name;
      });
    }
  }

  void _save() {
    final amountCents = _parsedAmountCents();
    if (amountCents == null) return;
    Navigator.of(context).pop(
      AnalyticsEditResult(
        amountCents: amountCents,
        transactionOccurredAt: _occurredAt.millisecondsSinceEpoch,
        classificationId: _classificationId,
        counterpartyLabel: _isCash ? null : _labelController.text.trim(),
        counterpartyPhone: (!_isCash && widget.tx.sourceType == 'SEND_MONEY') ? _phoneController.text.trim() : null,
        paybillAccountNumber: (!_isCash && widget.tx.sourceType == 'PAYBILL') ? _accountController.text.trim() : null,
        // An empty cost means 0 (T6's cost-optional precedent).
        transactionCostCents: _isCash ? null : ((double.tryParse(_costController.text.trim()) ?? 0) * 100).round(),
      ),
    );
  }

  String get _labelFieldLabel => switch (widget.tx.sourceType) {
    'PAYBILL' => 'Business name',
    'BUY_GOODS' => 'Merchant name',
    _ => 'Receiver name',
  };

  Widget _input(Key key, TextEditingController controller, {TextInputType? keyboard, bool onChange = false}) {
    final p = widget.palette;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: c, width: 1.5),
    );
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboard,
      cursorColor: p.primary,
      style: TextStyle(fontSize: 13, color: p.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: p.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: border(p.line),
        focusedBorder: border(p.primary),
        border: border(p.line),
      ),
      onChanged: onChange ? (_) => setState(() {}) : null,
    );
  }

  List<Widget> _field(String label, Widget input) => [analyticsFieldLabel(widget.palette, label), input];

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final tx = widget.tx;
    Widget group(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [children[0], const SizedBox(height: 4), ...children.skip(1)],
    );
    return BottomSheetShell(
      palette: p,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Edit transaction',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
              ),
            ),
            TextButton.icon(
              key: const Key('editDeleteButton'),
              onPressed: () => Navigator.of(context).pop(const AnalyticsDeleteRequest()),
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: p.diffUp),
              label: Text(
                'Delete',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.diffUp),
              ),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
        Text(
          '${tx.displayName} · ${sourceTypeName(tx.sourceType)}${tx.sourceType == 'CASH' ? '' : ' · ${tx.displayCode}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mutedInk),
        ),
        group(
          _field(
            'Amount (Ksh)',
            _input(
              const Key('editAmountField'),
              _amountController,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              onChange: true,
            ),
          ),
        ),
        group([
          analyticsFieldLabel(p, 'Date & time'),
          Row(
            children: [
              Expanded(
                child: Text(
                  _fmtEditDateTime(_occurredAt, DateTime.now()),
                  key: const Key('editDateTimeText'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                ),
              ),
              TextButton(
                key: const Key('editDateTimeChangeLink'),
                onPressed: _pickDateTime,
                child: Text(
                  'Change',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.primary),
                ),
              ),
            ],
          ),
        ]),
        if (!_isCash) ...[
          group(_field(_labelFieldLabel, _input(const Key('editLabelField'), _labelController))),
          if (tx.sourceType == 'SEND_MONEY')
            group(
              _field('Phone', _input(const Key('editPhoneField'), _phoneController, keyboard: TextInputType.phone)),
            ),
          if (tx.sourceType == 'PAYBILL')
            group(_field('Account number', _input(const Key('editAccountField'), _accountController))),
          group(
            _field(
              'Transaction cost (Ksh)',
              _input(
                const Key('editCostField'),
                _costController,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ),
        ],
        group([
          analyticsFieldLabel(p, 'Classification'),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(
                    'Classification: $_classificationName',
                    key: const Key('editClassificationChosen'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.onPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: const Key('editChooseClassificationButton'),
                onPressed: _openClassificationPicker,
                child: Text(
                  'Change',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.primary),
                ),
              ),
            ],
          ),
        ]),
        AnalyticsSheetActions(
          palette: p,
          cancelKey: const Key('editCancelButton'),
          primaryKey: const Key('editSaveButton'),
          primaryLabel: 'Save',
          onPrimary: _parsedAmountCents() != null ? _save : null,
        ),
      ],
    );
  }
}

/// The edit form's classification chooser: the real Add-flow pickers
/// (`MpesaClassificationPicker` locked to the row's type, or Cash's flat
/// `FlatClassificationPicker`), both painted with the edit sheet's palette.
class _EditClassificationPickerSheet extends StatelessWidget {
  const _EditClassificationPickerSheet({required this.db, required this.sourceType, required this.palette});

  final Database db;
  final String sourceType;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return BottomSheetShell(
      palette: p,
      children: [
        Text(
          'Choose a classification',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
        ),
        sourceType == 'CASH'
            ? FlatClassificationPicker(
                db: db,
                palette: p,
                onClassificationSelected: (item) => Navigator.of(context).pop(item),
              )
            : MpesaClassificationPicker(
                db: db,
                palette: p,
                groupCode: sourceType,
                onClassificationSelected: (item) => Navigator.of(context).pop(item),
              ),
      ],
    );
  }
}
