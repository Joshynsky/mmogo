import 'package:flutter/material.dart';

import '../../../data/backup/auto_backup_service.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../../platform/storage_bridge.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'backup_widgets.dart';
import '../../widgets/palette_alert_dialog.dart';

/// What the user does on the Auto-backup card: switch it on or off, choose a
/// folder, change N and K. Order of warnings (PM, criteria 23 and 24): the
/// unencrypted-file warning W1 is shown in a sheet BEFORE the folder picker
/// opens; the cloud-sync notice W2 is shown right after a folder is picked,
/// and only then (never when the page is reopened with a stored folder).
class AutoBackupFlow {
  AutoBackupFlow({this.service, this.bridge, required this.onChanged});

  /// Test seams (default: the app's own service and the real bridge).
  final AutoBackupService? service;
  final StorageBridge Function()? bridge;

  /// Called after any change so the page re-reads the prefs.
  final VoidCallback onChanged;

  AutoBackupService get _svc => service ?? AutoBackupService.instance;
  StorageBridge get _bridge => (bridge ?? () => StorageBridge.instance)();

  /// Switch on: the switch turns on at once ("On. Choose a folder to start.")
  /// and the setup sheet opens when no folder is stored yet. Switch off:
  /// releases the folder permission and clears the folder keys.
  Future<void> toggle(BuildContext context, bool on, {required bool hasFolder}) async {
    if (!on) {
      await _svc.turnOff();
      onChanged();
      return;
    }
    await BackupPrefs.writeEnabled(true);
    onChanged();
    if (!hasFolder && context.mounted) await chooseFolder(context);
  }

  /// Setup sheet (W1) -> OS folder picker -> cloud notice (W2) -> use it.
  Future<void> chooseFolder(BuildContext context) async {
    final n = await BackupPrefs.readEveryN();
    final k = await BackupPrefs.readKeepK();
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetupSheet(palette: AppPalette.of(context), everyN: n, keepK: k),
    );
    if (go != true) return;
    while (context.mounted) {
      PickedFolder? pick;
      var pickFailed = false;
      try {
        pick = await _bridge.pickFolder();
      } catch (_) {
        pickFailed = true;
      }
      if (!context.mounted) return;
      if (pickFailed) {
        _say(context, 'Could not open the folder picker. Try again.');
        return;
      }
      if (pick == null) return; // cancelled: nothing changed
      final use = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PaletteAlertDialog(
          title: const Text(kCloudSyncTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(kCloudSyncNotice),
              const SizedBox(height: 10),
              Text(pick!.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('cloudChooseAnother'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Choose another folder'),
            ),
            FilledButton(
              key: const Key('cloudUseFolder'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Use this folder'),
            ),
          ],
        ),
      );
      if (use == true) {
        final ok = await _svc.useFolder(pick);
        onChanged();
        if (context.mounted) {
          _say(context, ok ? autoBackupIsOnToast(n) : 'Could not save the folder choice. Try again.');
        }
        return;
      }
      await _svc.releaseUnused(pick); // declined: give the permission back
    }
  }

  Future<void> stepEveryN(int delta) async {
    final v = (await BackupPrefs.readEveryN()) + delta;
    await BackupPrefs.writeEveryN(v.clamp(BackupPrefs.minEveryN, BackupPrefs.maxEveryN));
    onChanged();
  }

  Future<void> stepKeepK(int delta) async {
    final v = (await BackupPrefs.readKeepK()) + delta;
    await BackupPrefs.writeKeepK(v.clamp(BackupPrefs.minKeepK, BackupPrefs.maxKeepK));
    onChanged();
  }

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SetupSheet extends StatelessWidget {
  const _SetupSheet({required this.palette, required this.everyN, required this.keepK});

  final AppPalette palette;
  final int everyN;
  final int keepK;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kAutoBackupSetupTitle,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: palette.ink),
            ),
            const SizedBox(height: 10),
            BackupPara(autoBackupSetupIntro(everyN, keepK), palette: palette),
            BackupWarning(palette: palette, text: kBackupFileWarning, key: const Key('setupWarning')),
            BackupPara(kAutoBackupFolderHint, palette: palette, bottom: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('setupNotNow'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('setupChooseFolder'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Choose folder'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
