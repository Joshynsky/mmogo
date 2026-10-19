/// §AUTOREAD.UI.CONSENT — the sheet shown BEFORE the system permission dialogs
/// the first time Read is turned on (Judge condition 10: one plain lead
/// sentence, the legal detail behind "More details"). Agree is the only way on.
/// Autoread flavor only.
library;

import 'package:flutter/material.dart';

import '../../ui/theme/app_colors.dart';
import 'settings_autoread_copy.dart';

/// Opens the consent sheet. True only when the user taps Agree; Not now, the
/// scrim and Back answer false and change nothing.
Future<bool> showConsentSheet(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ConsentSheet(),
  );
  return r ?? false;
}

class ConsentSheet extends StatefulWidget {
  const ConsentSheet({super.key});

  @override
  State<ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<ConsentSheet> {
  bool _more = false;
  bool _done = false;

  void _close(bool agreed) {
    if (_done) return; // a double tap answers once
    _done = true;
    Navigator.of(context).pop(agreed);
  }

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
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  key: const Key('consentScroll'),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          kConsentTitle,
                          style: TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(kConsentLead, style: TextStyle(fontSize: 14.5, height: 1.45, color: p.ink)),
                      const SizedBox(height: 6),
                      TextButton(
                        key: const Key('consentMore'),
                        style: TextButton.styleFrom(minimumSize: const Size(64, 44), alignment: Alignment.centerLeft),
                        onPressed: () => setState(() => _more = !_more),
                        child: Text(_more ? kConsentLess : kConsentMore),
                      ),
                      if (_more)
                        for (final line in kConsentDetailLines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(line, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink)),
                          ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const Key('consentAgree'),
                      style: FilledButton.styleFrom(minimumSize: minSize),
                      onPressed: () => _close(true),
                      child: const Text(kConsentAgree),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('consentNotNow'),
                      style: TextButton.styleFrom(minimumSize: minSize),
                      onPressed: () => _close(false),
                      child: const Text(kConsentNotNow),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
