import 'package:flutter/material.dart';

import '../../../data/prefs/backup_prefs.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import '../settings/settings_widgets.dart';
import 'auto_backup_state.dart';
import 'backup_format.dart';
import 'backup_widgets.dart';
import 'hold_step_button.dart';

/// The Auto-backup card on the Backup page (mock `autoCard`). Stateless: the
/// page owns the [AutoBackupState]; every action goes out through callbacks
/// (implemented by `AutoBackupFlow`).
///
/// States: off (just the switch); on without a folder; on and working (folder,
/// N, K, status line, W1); on and last attempt failed (banner); paused (banner
/// with "Choose folder", steppers off, "No automatic retry while paused").
class AutoBackupCard extends StatelessWidget {
  const AutoBackupCard({
    super.key,
    required this.palette,
    required this.state,
    required this.onToggle,
    required this.onChooseFolder,
    required this.onEveryN,
    required this.onKeepK,
  });

  final AppPalette palette;
  final AutoBackupState state;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChooseFolder;

  /// Steps by a signed amount: +1 or -1 for a tap, more while a button is held.
  final ValueChanged<int> onEveryN;
  final ValueChanged<int> onKeepK;

  String get _subtitle {
    if (!state.enabled) return kAutoBackupOffSubtitle;
    if (state.paused) return 'On, but paused';
    if (!state.hasFolder) return kAutoBackupOnNoFolderSubtitle;
    return autoBackupOnSubtitle(state.everyN);
  }

  String get _status {
    if (state.paused) return kAutoBackupPausedStatus;
    if (!state.hasFolder) return '';
    final left = state.everyN - state.sinceCount;
    final more = left < 0 ? 0 : left;
    final last = state.lastAt;
    if (last == null) {
      return 'No auto-backup yet. The first one is made after ${state.everyN} saved '
          '${state.everyN == 1 ? 'entry' : 'entries'}.';
    }
    return 'Last auto-backup: ${formatBackupTime(last)}. $more more saved ${more == 1 ? 'entry' : 'entries'} '
        'until the next one.';
  }

  @override
  Widget build(BuildContext context) {
    final on = state.enabled;
    final children = <Widget>[
      SettingsToggle(
        key: const Key('autoBackupSwitch'),
        palette: palette,
        icon: Icons.autorenew_rounded,
        label: 'Auto-backup',
        subtitle: _subtitle,
        value: on,
        first: true,
        onChanged: onToggle,
      ),
    ];
    if (on) {
      if (state.paused) {
        children.add(_banner(
          BackupWarning(
            key: const Key('autoBackupPausedBanner'),
            palette: palette,
            title: kAutoBackupPausedBannerTitle,
            text: kAutoBackupPausedBannerBody,
            action: _chooseButton(),
          ),
        ));
      } else if (!state.hasFolder) {
        children.add(_banner(
          BackupWarning(
            key: const Key('autoBackupNoFolderBanner'),
            palette: palette,
            text: kAutoBackupNoFolderBanner,
            action: _chooseButton(),
          ),
        ));
      }
      if (state.lastFailed) {
        children.add(_banner(
          BackupWarning(key: const Key('autoBackupFailedBanner'), palette: palette, text: kAutoBackupFailedBanner),
        ));
      }
      children.add(SettingsLink(
        key: const Key('autoBackupFolderRow'),
        palette: palette,
        icon: Icons.folder_outlined,
        label: 'Backup folder',
        subtitle: state.hasFolder
            ? '${state.folderName ?? 'Chosen folder'}${state.paused ? ' (not available)' : ''}'
            : 'Not chosen yet',
        onTap: onChooseFolder,
      ));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(kAutoBackupFolderHint, style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk)),
      ));
      children.add(_Stepper(
        keyName: 'autoEveryN',
        palette: palette,
        icon: Icons.format_list_numbered_rounded,
        title: 'Back up every N entries',
        subtitle: 'After every ${state.everyN} saved ${state.everyN == 1 ? 'entry' : 'entries'}',
        value: state.everyN,
        min: BackupPrefs.minEveryN,
        max: BackupPrefs.maxEveryN,
        unit: 'entries',
        disabled: state.paused,
        onStep: onEveryN,
        accelerate: true,
      ));
      children.add(_Stepper(
        keyName: 'autoKeepK',
        palette: palette,
        icon: Icons.inventory_2_outlined,
        title: 'Keep K files',
        subtitle: 'Older auto-backup files beyond ${state.keepK} are deleted',
        value: state.keepK,
        min: BackupPrefs.minKeepK,
        max: BackupPrefs.maxKeepK,
        unit: 'files',
        disabled: state.paused,
        onStep: onKeepK,
      ));
      if (_status.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _status,
            key: const Key('autoBackupStatus'),
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
          ),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: BackupWarning(palette: palette, text: kBackupFileWarning, bottomGap: 0),
      ));
    }
    return SettingsCard(
      palette: palette,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _banner(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: w);

  Widget _chooseButton() => FilledButton(
        key: const Key('autoBackupChooseFolder'),
        onPressed: onChooseFolder,
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          visualDensity: VisualDensity.compact,
          shape: const StadiumBorder(),
        ),
        child: const Text('Choose folder'),
      );
}

/// A row with a minus button, the number and a plus button (mock `.nstep`).
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyName,
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.disabled,
    required this.onStep,
    this.accelerate = false,
  });

  /// Holding the buttons grows the step to 5 then 10 (the wide N range).
  final bool accelerate;
  final String keyName;
  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final String unit;
  final bool disabled;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SettingsRowIcon(icon: icon, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                ],
              ),
            ),
            HoldStepButton(
              buttonKey: Key('${keyName}Less'),
              tooltip: 'Fewer $unit',
              icon: Icons.remove_rounded,
              direction: -1,
              value: value,
              min: min,
              max: max,
              enabled: !disabled,
              accelerate: accelerate,
              onStep: onStep,
            ),
            SizedBox(
              width: 30,
              child: Text(
                '$value',
                key: Key('${keyName}Value'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.ink),
              ),
            ),
            HoldStepButton(
              buttonKey: Key('${keyName}More'),
              tooltip: 'More $unit',
              icon: Icons.add_rounded,
              direction: 1,
              value: value,
              min: min,
              max: max,
              enabled: !disabled,
              accelerate: accelerate,
              onStep: onStep,
            ),
          ],
        ),
      ),
    );
  }
}
