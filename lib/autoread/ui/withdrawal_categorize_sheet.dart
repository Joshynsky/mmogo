/// §AUTOREAD.WITHDRAWAL_CATEGORIZE_SHEET (0.2.1) - the Categorize sheet of a withdrawal:
/// "What was this money for?" with the dashed Cash only chip first, the category chips, one
/// grey sentence, and a button that reads Save (Cash only) or "Add Cash - Rent". The
/// withdrawal itself is recorded either way; the choice only adds the linked Cash entry.
/// Holds no repository: [onSave] gets the chosen category id (null = Cash only), once.
/// Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../ui/copy/withdrawal_copy.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/error_notes.dart';
import '../../ui/widgets/withdrawal_use_block.dart';
import 'notifications_autoread_copy.dart' show kActionCategorize;

Future<void> showWithdrawalCategorizeSheet(
  BuildContext context, {
  required String title,
  required int amountCents,
  required List<WdChoice> choices,
  required Future<void> Function(int? categoryId) onSave,
  Future<WdCreateResult> Function(String name)? onCreate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WithdrawalCategorizeSheet(title: title, amountCents: amountCents, choices: choices, onSave: onSave, onCreate: onCreate),
  );
}

class WithdrawalCategorizeSheet extends StatefulWidget {
  const WithdrawalCategorizeSheet({
    super.key,
    required this.title,
    required this.amountCents,
    required this.choices,
    required this.onSave,
    this.onCreate,
  });

  /// What the message is ("Withdrew Ksh 2,000 from Test Agent").
  final String title;
  final int amountCents;
  final List<WdChoice> choices;
  final Future<void> Function(int? categoryId) onSave;

  /// Creates a category from the "+ New" chip (null = no chip).
  final Future<WdCreateResult> Function(String name)? onCreate;

  @override
  State<WithdrawalCategorizeSheet> createState() => _WithdrawalCategorizeSheetState();
}

class _WithdrawalCategorizeSheetState extends State<WithdrawalCategorizeSheet> {
  int? _picked;
  bool _saving = false;
  String? _error;
  late List<WdChoice> _choices = widget.choices;

  String? get _pickedName => _choices.where((c) => c.id == _picked).map((c) => c.name).firstOrNull;

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    setState(() => _error = null);
    try {
      await widget.onSave(_picked);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      _saving = false;
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom > mq.viewPadding.bottom ? mq.viewInsets.bottom : mq.viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.88),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(kActionCategorize, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
                      ),
                    ),
                    IconButton(
                      key: const Key('wdSheetClose'),
                      tooltip: 'Close',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      icon: Icon(Icons.close, color: p.ink),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                Text(widget.title, key: const Key('wdSheetTitle'), style: TextStyle(fontSize: 13, color: p.softInk)),
                const SizedBox(height: 14),
                WithdrawalUseBlock(
                  palette: p,
                  choices: _choices,
                  onCreate: widget.onCreate == null
                      ? null
                      : (n) async {
                          final r = await widget.onCreate!(n);
                          if (r.choices != null && mounted) setState(() => _choices = r.choices!);
                          return r;
                        },
                  selectedId: _picked,
                  sentence: wdSentenceAdd(categoryId: _picked, categoryName: _pickedName, amountCents: widget.amountCents),
                  onChanged: (id) => setState(() => _picked = id),
                ),
                const SizedBox(height: 14),
                if (_error != null) FieldError(_error!, padding: const EdgeInsets.only(bottom: 8)),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const Key('wdSheetSave'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: p.onPrimary,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    child: Text(_picked == null ? 'Save' : wdAddCashButton(_pickedName ?? '')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
