import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../copy/withdrawal_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/withdrawal_use_block.dart';
import '../../widgets/withdrawal_use_create.dart';

/// §ADD.WITHDRAWAL_USE (0.2.1) — "What was this money for?" under `Category: Withdrawal` on
/// Add (type W). Cash only (default) or a Cash category; Save then adds the linked Cash entry.
/// [onChanged] gets (null, null) for Cash only.
class WithdrawalUseRow extends StatefulWidget {
  const WithdrawalUseRow({
    super.key,
    required this.db,
    required this.palette,
    required this.selectedId,
    required this.amountCents,
    required this.onChanged,
  });

  final Database db;
  final AppPalette palette;
  final int? selectedId;
  final int? amountCents;
  final void Function(int? id, String? name) onChanged;

  @override
  State<WithdrawalUseRow> createState() => _WithdrawalUseRowState();
}

class _WithdrawalUseRowState extends State<WithdrawalUseRow> {
  List<WdChoice> _choices = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final cats = await loadWithdrawalUseChoices(widget.db);
      if (mounted) setState(() => _choices = cats);
    } catch (_) {
      // No category chips; Cash only still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _choices.where((c) => c.id == widget.selectedId).map((c) => c.name).firstOrNull;
    return Padding(
      key: const Key('addWithdrawalUse'),
      padding: const EdgeInsets.only(top: 14),
      child: WithdrawalUseBlock(
        palette: widget.palette,
        choices: _choices,
        selectedId: widget.selectedId,
        sentence: wdSentenceAdd(categoryId: widget.selectedId, categoryName: name, amountCents: widget.amountCents),
        onCreate: (n) async {
          final r = await createWithdrawalUseCategory(widget.db, n);
          if (r.choices != null && mounted) setState(() => _choices = r.choices!);
          return r;
        },
        onChanged: (id) => widget.onChanged(id, _choices.where((c) => c.id == id).map((c) => c.name).firstOrNull),
      ),
    );
  }
}
