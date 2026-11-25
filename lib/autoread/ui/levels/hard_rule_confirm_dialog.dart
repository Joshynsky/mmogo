/// §AUTOREAD.LEVELS.HARD_RULE_CONFIRM: the question before a person is put on Auto-record (mock dialog
/// "hard", from the level sheet and the offer card). Two bodies: no ceiling, or with a ceiling.
/// Shown only for a NEW Auto-record, never when only the ceiling changes (the caller decides).
library;

import 'package:flutter/material.dart';

import 'hard_rule_copy.dart';
import 'levels_copy.dart' show kLevelSheetCancel;

/// Asks "Auto-record {name}?". True only when the user taps Turn on; Cancel, scrim and Back give false.
Future<bool> showHardRuleConfirm(BuildContext context,
    {required String name, required String category, int? ceilingCents}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => HardRuleConfirmDialog(name: name, category: category, ceilingCents: ceilingCents),
  );
  return r ?? false;
}

class HardRuleConfirmDialog extends StatelessWidget {
  const HardRuleConfirmDialog({super.key, required this.name, required this.category, this.ceilingCents});
  final String name;
  final String category;
  final int? ceilingCents;

  @override
  Widget build(BuildContext context) {
    const minSize = Size(64, 44);
    final c = ceilingCents;
    return AlertDialog(
      title: Text(hardConfirmTitle(name), key: const Key('hardConfirmTitle')),
      content: SingleChildScrollView(
        child: Text(
          c == null ? hardConfirmBodyNoCeiling(name, category) : hardConfirmBodyCeiling(name, category, c),
          key: const Key('hardConfirmBody'),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hardConfirmCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kLevelSheetCancel),
        ),
        FilledButton(
          key: const Key('hardConfirmOk'),
          style: FilledButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kHardConfirmTurnOn),
        ),
      ],
    );
  }
}
