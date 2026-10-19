/// §AUTOREAD.UI.SETTINGS — the Settings card for reading M-Pesa messages
/// (FE-N7): the Read switch with a plain status line, the "Capture is on but
/// not working: fix" row (only when Read is on and a permission is missing),
/// Delete held messages (with a confirmation) and the restricted-settings help.
///
/// Placed right after "Your data" in Settings: what it holds and removes is
/// the user's data, and the help and delete rows belong next to the other
/// data actions. Autoread flavor only; the Settings screen reaches it inside
/// `if (kAutoReadCompiled)`.
library;

import 'package:flutter/material.dart';

import '../../ui/screens/settings/settings_widgets.dart';
import '../../ui/theme/app_colors.dart';
import '../logic/reading_controller.dart';
import 'consent_sheet.dart';
import 'restricted_help_sheet.dart';
import 'settings_autoread_copy.dart';

class ReadingSettingsSection extends StatefulWidget {
  /// [controller] null = the app's one controller ([ReadingControllerHolder]);
  /// when that is unset too, nothing is drawn.
  const ReadingSettingsSection({super.key, this.controller});

  final ReadingController? controller;

  @override
  State<ReadingSettingsSection> createState() => _ReadingSettingsSectionState();
}

class _ReadingSettingsSectionState extends State<ReadingSettingsSection> with WidgetsBindingObserver {
  ReadingState? _state;
  bool _busy = false;
  String? _message;
  // True when a fix attempt ended still blocked: the fix row then says so.
  bool _stillBlocked = false;

  ReadingController? get _c => widget.controller ?? ReadingControllerHolder.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android settings: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = _c;
    if (c == null) return;
    final s = await c.state();
    if (!mounted) return;
    setState(() {
      _state = s;
      if (!s.broken) _stillBlocked = false;
    });
  }

  Future<void> _runBusy(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deniedText(Denied d) => switch (d) {
        Denied.sms => kReadDeniedSms,
        Denied.notifications => kReadDeniedNotifications,
        Denied.blocked => kReadDeniedBlocked,
      };

  Future<void> _onSwitch(bool wantOn) => _runBusy(() async {
        final c = _c;
        if (c == null) return;
        _message = null;
        if (wantOn) {
          // Consent first, once; Agree is the only way to the system dialogs.
          if (!await c.hasConsent()) {
            if (!mounted) return;
            final agreed = await showConsentSheet(context);
            if (!agreed) return;
            if (!await c.recordConsent()) {
              if (mounted) setState(() => _message = kReadFailed);
              return;
            }
          }
          final r = await c.turnOn();
          if (!mounted) return;
          switch (r.outcome) {
            case TurnOnOutcome.on:
              _message = null;
            case TurnOnOutcome.denied:
              _message = _deniedText(r.denied!);
            case TurnOnOutcome.needsConsent:
            case TurnOnOutcome.failed:
              _message = kReadFailed;
          }
        } else {
          final r = await c.turnOff();
          if (!mounted) return;
          _message = switch (r) {
            TurnOffResult.off => null,
            TurnOffResult.stillOn => kReadStillOn,
          };
        }
        await _refresh();
      });

  Future<void> _onFix() => _runBusy(() async {
        final c = _c;
        if (c == null) return;
        final r = await c.turnOn();
        if (!mounted) return;
        if (r.outcome == TurnOnOutcome.denied) {
          _stillBlocked = true;
          await _refresh();
          if (mounted) await _openHelp();
        } else {
          _stillBlocked = false;
          await _refresh();
        }
      });

  Future<void> _openHelp() {
    final c = _c;
    return showRestrictedHelpSheet(
      context,
      onOpenAppSettings: () async {
        await c?.openAppSettings();
      },
    );
  }

  Future<void> _onDeleteHeld() async {
    final c = _c;
    if (c == null || _busy) return;
    final yes = await showDialog<bool>(context: context, builder: (_) => const _DeleteHeldDialog());
    if (yes != true || !mounted) return;
    await _runBusy(() async {
      final ok = await c.deleteHeld();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ok ? kDeleteHeldDone : kDeleteHeldFailed)));
      await _refresh();
    });
  }

  String _status(ReadingState s) {
    if (_busy) return kReadStatusWorking;
    final m = _message;
    if (m != null) return m;
    if (!s.available) return kReadStatusUnavailable;
    return s.on ? kReadStatusOn : kReadStatusOff;
  }

  String _fixSubtitle(ReadingState s) {
    if (_stillBlocked) return kFixStillBlocked;
    if (!s.smsAllowed && !s.notificationsAllowed) return kFixBoth;
    return !s.smsAllowed ? kFixSms : kFixNotifications;
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (_c == null || s == null) return const SizedBox.shrink();
    final AppPalette palette = AppPalette.of(context);
    return Column(
      key: const Key('readingSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kReadingSectionLabel, palette: palette),
        SettingsCard(
          palette: palette,
          child: Column(
            children: [
              SettingsToggle(
                key: const Key('readingSwitch'),
                palette: palette,
                icon: Icons.sms_outlined,
                label: kReadLabel,
                subtitle: _status(s),
                first: true,
                value: s.on,
                onChanged: (!s.available || _busy) ? null : _onSwitch,
              ),
              if (s.broken)
                SettingsLink(
                  key: const Key('readingFixRow'),
                  palette: palette,
                  icon: Icons.build_circle_outlined,
                  label: kFixLabel,
                  subtitle: _fixSubtitle(s),
                  warningDot: true,
                  onTap: _busy ? null : _onFix,
                ),
              SettingsLink(
                key: const Key('readingDeleteHeld'),
                palette: palette,
                icon: Icons.delete_sweep_outlined,
                label: kDeleteHeldLabel,
                subtitle: s.heldCount == 0 ? kDeleteHeldNone : deleteHeldSubtitle(s.heldCount),
                onTap: (s.available && s.heldCount > 0 && !_busy) ? _onDeleteHeld : null,
              ),
              SettingsLink(
                key: const Key('readingHelpRow'),
                palette: palette,
                icon: Icons.help_outline,
                label: kHelpRowLabel,
                subtitle: kHelpRowSubtitle,
                onTap: _openHelp,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteHeldDialog extends StatelessWidget {
  const _DeleteHeldDialog();

  @override
  Widget build(BuildContext context) {
    const minSize = Size(64, 44);
    return AlertDialog(
      title: const Text(kDeleteHeldTitle),
      content: const Text(kDeleteHeldBody),
      actions: [
        TextButton(
          key: const Key('deleteHeldCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kDeleteHeldCancel),
        ),
        FilledButton(
          key: const Key('deleteHeldConfirm'),
          style: FilledButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kDeleteHeldConfirm),
        ),
      ],
    );
  }
}
