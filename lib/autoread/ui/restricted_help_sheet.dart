/// §AUTOREAD.UI.HELP — the plain steps for a phone that blocks SMS for mmogo
/// (restricted settings), from the T1 Oppo walk, wording kept generic.
/// Autoread flavor only.
library;

import 'package:flutter/material.dart';

import '../../ui/theme/app_colors.dart';
import 'settings_autoread_copy.dart';

/// Opens the help. [onOpenAppSettings] runs when the user taps "Open app
/// settings" (the sheet stays open so the steps can be read on return).
Future<void> showRestrictedHelpSheet(
  BuildContext context, {
  required Future<void> Function() onOpenAppSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RestrictedHelpSheet(onOpenAppSettings: onOpenAppSettings),
  );
}

class RestrictedHelpSheet extends StatelessWidget {
  const RestrictedHelpSheet({super.key, required this.onOpenAppSettings});

  final Future<void> Function() onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    const minSize = Size.fromHeight(44);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewPadding.bottom),
      child: Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SingleChildScrollView(
          key: const Key('helpScroll'),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  kHelpTitle,
                  style: TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w800, color: p.ink),
                ),
              ),
              const SizedBox(height: 10),
              Text(kHelpIntro, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
              const SizedBox(height: 10),
              for (var i = 0; i < kHelpSteps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    label: 'Step ${i + 1}. ${kHelpSteps[i]}',
                    excludeSemantics: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text('${i + 1}.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink)),
                        ),
                        Expanded(
                          child: Text(kHelpSteps[i], style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(kHelpNote, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('helpOpenSettings'),
                style: FilledButton.styleFrom(minimumSize: minSize),
                onPressed: () => onOpenAppSettings(),
                child: const Text(kHelpOpen),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('helpClose'),
                style: TextButton.styleFrom(minimumSize: minSize),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(kHelpClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
