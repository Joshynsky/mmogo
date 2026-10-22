/// §AUTOREAD.UI.CONSENT — the ONE consent screen shown BEFORE the system
/// permission dialogs (PM-approved mock `consent-reading.html`, 21-10-2026):
/// an individual switch per consent, (1) "Read M-Pesa messages" and (2) "Parse
/// from the notification" (greyed while 1 is off), explicit Allow and Not now
/// buttons, and a plain line that everything can be changed later in Settings.
/// No master switch. Both switches start ON (PM 21-10-2026); nothing takes
/// effect until Allow is pressed. On a Xiaomi-family phone an Autostart row
/// with an "Open Autostart settings" button is added (it is not a switch).
/// Autoread flavor only.
library;

import 'package:flutter/material.dart';

import '../../ui/screens/settings/settings_widgets.dart';
import '../../ui/theme/app_colors.dart';
import 'settings_autoread_copy.dart';

/// What the user chose when they pressed Allow with Read on.
class ConsentChoice {
  const ConsentChoice({required this.parse});

  /// Switch 2 at the moment Allow was pressed. (Switch 1 is on by definition:
  /// with it off, Allow turns nothing on and the sheet answers null.)
  final bool parse;
}

/// Opens the consent screen. Returns the choice only when the user pressed
/// Allow with switch 1 on. Not now, the scrim, Back, and Allow with switch 1
/// off answer null and change nothing (the mock's result line: "Nothing is
/// turned on").
///
/// [autostartHelp] true on a Xiaomi-family phone (decided in Kotlin):
/// the Autostart row shows. [onOpenAutostart] runs only from its button.
Future<ConsentChoice?> showConsentSheet(
  BuildContext context, {
  bool autostartHelp = false,
  Future<void> Function()? onOpenAutostart,
}) {
  return showModalBottomSheet<ConsentChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ConsentSheet(autostartHelp: autostartHelp, onOpenAutostart: onOpenAutostart),
  );
}

class ConsentSheet extends StatefulWidget {
  const ConsentSheet({super.key, this.autostartHelp = false, this.onOpenAutostart});

  final bool autostartHelp;
  final Future<void> Function()? onOpenAutostart;

  @override
  State<ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<ConsentSheet> {
  bool _more = false;
  bool _done = false;
  bool _read = true;
  bool _parse = true;

  void _close(ConsentChoice? answer) {
    if (_done) return; // a double tap answers once
    _done = true;
    Navigator.of(context).pop(answer);
  }

  void _allow() => _close(_read ? ConsentChoice(parse: _parse) : null);

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
                      SettingsCard(
                        palette: p,
                        child: Column(
                          children: [
                            SettingsToggle(
                              key: const Key('consentReadSwitch'),
                              palette: p,
                              icon: Icons.sms_outlined,
                              label: kReadLabel,
                              subtitle: kConsentReadDesc,
                              first: true,
                              value: _read,
                              onChanged: (v) => setState(() => _read = v),
                            ),
                            SettingsToggle(
                              key: const Key('consentParseSwitch'),
                              palette: p,
                              icon: Icons.touch_app_outlined,
                              label: kParseLabel,
                              subtitle: _read ? kConsentParseDesc : '$kConsentParseDesc $kParseGreyLine',
                              value: _read && _parse,
                              onChanged: _read ? (v) => setState(() => _parse = v) : null,
                            ),
                          ],
                        ),
                      ),
                      if (widget.autostartHelp) ...[
                        const SizedBox(height: 10),
                        AutostartBlock(
                          key: const Key('consentAutostart'),
                          onOpen: widget.onOpenAutostart,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        kConsentFooter,
                        key: const Key('consentFooter'),
                        style: TextStyle(fontSize: 13, height: 1.45, color: p.ink),
                      ),
                      // moved to first screen, PM 22-10-2026
                      const SizedBox(height: 8),
                      Text(
                        kConsentAndroidPrompt,
                        key: const Key('consentAndroidPrompt'),
                        style: TextStyle(fontSize: 13, height: 1.45, color: p.ink),
                      ),
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
                      key: const Key('consentAllow'),
                      style: FilledButton.styleFrom(minimumSize: minSize),
                      onPressed: _allow,
                      child: const Text(kConsentAllow),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('consentNotNow'),
                      style: TextButton.styleFrom(minimumSize: minSize),
                      onPressed: () => _close(null),
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

/// The Autostart explanation and its button (Xiaomi-family phones only). NOT a
/// switch: an app cannot toggle another OS setting. Used by the consent screen
/// and by Settings.
class AutostartBlock extends StatelessWidget {
  const AutostartBlock({super.key, required this.onOpen});

  /// Null = the button does nothing (no controller).
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kAutostartLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 3),
          Text(kAutostartBody, style: TextStyle(fontSize: 13, height: 1.45, color: p.ink)),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const Key('autostartOpen'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: onOpen == null ? null : () => onOpen!(),
            child: const Text(kAutostartButton),
          ),
        ],
      ),
    );
  }
}
