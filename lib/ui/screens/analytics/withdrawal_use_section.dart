import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/linked_cash_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../copy/withdrawal_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/withdrawal_use_block.dart';
import '../../widgets/withdrawal_use_create.dart';

/// The user's pick on a withdrawal: a category id, or null = Cash only.
class WithdrawalPick {
  const WithdrawalPick(this.categoryId);
  final int? categoryId;
}

/// §ANALYTICS.WITHDRAWAL_USE (0.2.1) — the "What was this money for?" block of the withdrawal
/// edit sheet. Loads the live linked entries and the Cash picker's categories itself.
/// One entry: its category is preselected and a change moves the entry. Several entries:
/// the chips are off, each entry is a row that opens its own sheet.
/// [onChanged] is called with (changed, categoryId) after every tap; changed = differs from
/// what the withdrawal had when the sheet opened.
class WithdrawalUseSection extends StatefulWidget {
  const WithdrawalUseSection({
    super.key,
    required this.db,
    required this.palette,
    required this.tx,
    required this.onChanged,
    required this.onOpenEntry,
  });

  final Database db;
  final AppPalette palette;
  final AnalyticsTransactionRow tx;
  final void Function(bool changed, int? categoryId) onChanged;
  final ValueChanged<int> onOpenEntry;

  @override
  State<WithdrawalUseSection> createState() => _WithdrawalUseSectionState();
}

class _WithdrawalUseSectionState extends State<WithdrawalUseSection> {
  List<LinkedCashEntry> _entries = const [];
  List<WdChoice> _choices = const [];
  bool _ready = false;
  int? _initialId;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<LinkedCashEntry> entries;
    final List<WdChoice> cats;
    try {
      entries = await LinkedCashDao.linkedEntriesOf(widget.db, widget.tx.id);
      cats = await loadWithdrawalUseChoices(widget.db);
    } catch (_) {
      return; // the block stays hidden; the rest of the sheet works as before
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _choices = [
        ...cats,
        // An entry made before the Cash list existed can sit in another group: keep it as a chip so it stays selected.
        for (final e in entries)
          if (entries.length == 1 && !cats.any((c) => c.id == e.classificationId)) WdChoice(e.classificationId, e.classificationName),
      ];
      _initialId = entries.length == 1 ? entries.first.classificationId : null;
      _selectedId = _initialId;
      _ready = true;
    });
  }

  String get _dayText => '${weekdayShort(widget.tx.occurredAt)}, ${fmtDayMonth(widget.tx.occurredAt)}';

  /// The single linked entry's category stays a chip even when it is not in the Cash list (made before it existed).
  List<WdChoice> _keepEntryCategory(List<WdChoice> cats) => [
        ...cats,
        for (final e in _entries)
          if (_entries.length == 1 && !cats.any((c) => c.id == e.classificationId)) WdChoice(e.classificationId, e.classificationName),
      ];

  String _nameOf(int? id) => id == null ? '' : _choices.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '';

  String _sentence() {
    final tx = widget.tx;
    final n = _entries.length;
    if (n == 0) {
      return wdSentenceNoEntry(
        categoryId: _selectedId,
        categoryName: _nameOf(_selectedId),
        amountCents: tx.amountCents,
        feeCents: tx.transactionCostCents ?? 0,
        dayText: _dayText,
      );
    }
    if (n == 1) {
      return wdSentenceOneEntry(
        categoryId: _selectedId,
        categoryName: _nameOf(_selectedId),
        entryCategory: _entries.first.classificationName,
        entryCents: _entries.first.amountCents,
        withdrawalCents: tx.amountCents,
      );
    }
    final spent = _entries.fold<int>(0, (s, e) => s + e.spentCents);
    return wdSentenceSplit(count: n, spentCents: spent, stillCashCents: tx.amountCents - spent);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    if (!_ready) return const SizedBox.shrink();
    final n = _entries.length;
    return Column(
      key: const Key('withdrawalUseSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WithdrawalUseBlock(
          palette: p,
          choices: _choices,
          selectedId: _selectedId,
          enabled: n <= 1,
          sentence: _sentence(),
          noteUnder: n == 1 ? kWdChangeAlsoChanges : null,
          onCreate: n <= 1
              ? (name) async {
                  final r = await createWithdrawalUseCategory(widget.db, name);
                  if (r.choices != null && mounted) setState(() => _choices = _keepEntryCategory(r.choices!));
                  return r;
                }
              : null,
          onChanged: (id) {
            setState(() => _selectedId = id);
            widget.onChanged(id != _initialId, id);
          },
        ),
        for (final e in _entries)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Material(
              color: p.track,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: InkWell(
                key: Key('wdEntryLink-${e.id}'),
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                onTap: () => widget.onOpenEntry(e.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(wdCashTitle(e.classificationName),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
                        ),
                        Text('${kshTrim(e.amountCents)} ›', style: TextStyle(fontSize: 11.5, color: p.mutedInk)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
