/// §AUTOREAD.SETTINGS.SUGGEST: the two Suggest rows in Settings (mock set_sugg,
/// set_after): the offer switch and the "Suggest after" picker (2 to 10,
/// default 3; shown only while the switch is on). Reads and writes through
/// [SuggestSettingsPort]; nothing is stored here.
/// 0.2.2 (mock ctl-a-set): the amber "Pause all Auto-record" row under them, the same switch as the
/// Remembered page's card (one [HardRulePausePort], so both stay in sync). Only while [autoRecordUi].
library;

import 'package:flutter/material.dart';

import '../../../ui/screens/settings/settings_widgets.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../levels/hard_rule_copy.dart';
import '../levels/hard_rule_pause_card.dart';
import '../levels/hard_rule_ports.dart';
import '../levels/levels_copy.dart';
import '../levels/levels_deps.dart';

class SuggestSettingsSection extends StatefulWidget {
  /// [port] null = the app's one ([LevelsDeps.instance]); when that is unset
  /// too, nothing is drawn.
  const SuggestSettingsSection({super.key, this.port, this.pause, this.bulk});
  final SuggestSettingsPort? port;

  /// The pause switch (0.2.2); null = the app's one ([LevelsDeps.instance]); none = no row.
  final HardRulePausePort? pause;

  /// For the resume toast's count; null = the app's one ([LevelsDeps.instance]).
  final RuleBulkOps? bulk;

  @override
  State<SuggestSettingsSection> createState() => _SuggestSettingsSectionState();
}

class _SuggestSettingsSectionState extends State<SuggestSettingsSection> {
  bool? _on;
  int _after = kSuggestAfterDefault;
  bool _busy = false;

  SuggestSettingsPort? get _port => widget.port ?? LevelsDeps.instance?.suggest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = _port;
    if (p == null) return;
    bool on = true;
    int n = kSuggestAfterDefault;
    try {
      on = await p.enabled();
      n = clampSuggestAfter(await p.after());
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _on = on;
      _after = n;
    });
  }

  void _say(String text) => PillToast.show(text);

  Future<void> _setOn(bool v) async {
    final p = _port;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    final ok = await p.setEnabled(v).catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _on = v;
    });
    if (!ok) _say(kSuggestSaveFailed);
  }

  Future<void> _pickAfter() async {
    final p = _port;
    if (p == null || _busy) return;
    final pick = await showDialog<int>(context: context, builder: (_) => _AfterDialog(current: _after));
    if (pick == null || !mounted) return;
    final n = clampSuggestAfter(pick);
    setState(() => _busy = true);
    final ok = await p.setAfter(n).catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _after = n;
    });
    if (!ok) _say(kSuggestSaveFailed);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (_port == null || on == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final pause = widget.pause ?? LevelsDeps.instance?.pause;
    return Column(
      key: const Key('suggestSettings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSuggestSectionLabel, palette: palette),
        SettingsCard(
          palette: palette,
          child: Column(children: [
            SettingsToggle(
              key: const Key('suggestSwitch'),
              palette: palette,
              icon: Icons.auto_awesome_outlined,
              label: kSuggestSwitchLabel,
              subtitle: kSuggestSwitchSub,
              first: true,
              value: on,
              onChanged: _busy ? null : _setOn,
            ),
            if (on)
              SettingsLink(
                key: const Key('suggestAfterRow'),
                palette: palette,
                icon: Icons.format_list_numbered,
                label: kSuggestAfterLabel,
                subtitle: '${suggestAfterOption(_after)}. $kSuggestAfterSub',
                onTap: _busy ? null : _pickAfter,
              ),
            if (autoRecordUi && pause != null) _PauseRow(port: pause, bulk: widget.bulk ?? LevelsDeps.instance?.bulk),
          ]),
        ),
      ],
    );
  }
}

/// The amber Settings row (mock `set_pause_row`): the whole row is one switch for a screen reader; the
/// row is tinted amber while paused (the words say it too, so the colour is not the only sign).
class _PauseRow extends StatefulWidget {
  const _PauseRow({required this.port, this.bulk});
  final HardRulePausePort port;
  final RuleBulkOps? bulk;

  @override
  State<_PauseRow> createState() => _PauseRowState();
}

class _PauseRowState extends State<_PauseRow> with HardRulePauseWatch<_PauseRow> {
  bool _busy = false;

  @override
  HardRulePausePort? get pausePort => widget.port;

  Future<void> _set(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    await setHardRulePause(widget.port, widget.bulk, v);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = paused;
    if (on == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final change = _busy ? null : () => _set(!on);
    return Semantics(
      container: true,
      toggled: on,
      enabled: !_busy,
      label: kHardPauseSettingsTitle,
      hint: kHardPauseSettingsSub,
      onTap: change,
      excludeSemantics: true,
      child: Material(
        color: on ? palette.highlight : Colors.transparent,
        child: InkWell(
          key: const Key('hardPauseSettingsRow'),
          onTap: change,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              SettingsRowIcon(icon: Icons.pause_circle_outline, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(kHardPauseSettingsTitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                    const SizedBox(height: 2),
                    Text(kHardPauseSettingsSub, style: TextStyle(fontSize: 12, height: 1.35, color: on ? palette.ink : palette.mutedInk)),
                  ],
                ),
              ),
              hardPauseSwitch(palette, key: const Key('hardPauseSettingsSwitch'), value: on, onChanged: _busy ? null : _set),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The picker: 2 to 10, the current one marked. Pops the number.
class _AfterDialog extends StatelessWidget {
  const _AfterDialog({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text(kSuggestAfterLabel),
      children: [
        for (var n = kSuggestAfterMin; n <= kSuggestAfterMax; n++)
          SimpleDialogOption(
            key: Key('suggestAfter$n'),
            onPressed: () => Navigator.of(context).pop(n),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Icon(n == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                const SizedBox(width: 12),
                Expanded(child: Text(suggestAfterOption(n))),
              ]),
            ),
          ),
      ],
    );
  }
}
