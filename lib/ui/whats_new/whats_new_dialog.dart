import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../data/prefs/app_prefs.dart';
import '../../data/prefs/update_prefs.dart';
import '../../domain/whats_new/whats_new_gate.dart';
import '../copy/data_copy.dart';
import '../copy/whats_new_copy.dart';
import '../shell/routes.dart';
import 'whats_new_content.dart';

/// What the person chose in the modal.
enum WhatsNewChoice { gotIt, openBackup }

/// The 0.1.1 What's-new modal (signed-off prototype `whatsNew()`).
Future<WhatsNewChoice?> showWhatsNewDialog(BuildContext context) => showDialog<WhatsNewChoice>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) {
    // No palette colours here: AlertDialog is always the light Material
    // surface (AppTheme is light), so palette.ink in dark mode was pale text
    // on a pale dialog. The theme's own dialog text colour reads in both.
    TextSpan para(String lead, String body) => TextSpan(
      children: [
        TextSpan(text: lead, style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: body),
      ],
    );
    return AlertDialog(
      key: const Key('whatsNewDialog'),
      title: const Text(kWhatsNewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final span in [
              para(kWhatsNewBackupLead, kWhatsNewBackupBody),
              para(kUninstallErasesNotice, ' $kPhoneTransferNotice'),
              para(kWhatsNewInternetLead, kWhatsNewInternetBody),
              para(kWhatsNewUnsupportedLead, kWhatsNewUnsupportedBody),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text.rich(span, style: const TextStyle(fontSize: 14, height: 1.45)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('whatsNewOpenBackup'),
          onPressed: () => Navigator.of(ctx).pop(WhatsNewChoice.openBackup),
          child: const Text(kWhatsNewOpenBackup),
        ),
        FilledButton(
          key: const Key('whatsNewGotIt'),
          onPressed: () => Navigator.of(ctx).pop(WhatsNewChoice.gotIt),
          child: const Text(kWhatsNewGotIt),
        ),
      ],
    );
  },
);

/// Home's hook (B31): reads the stored version and the onboarding flag, asks
/// [WhatsNewGate], shows the modal once, remembers the version however it was
/// closed, and opens Backup and restore when asked. Never throws.
///
/// Test seams: [installedVersionName], [readSeenVersion], [writeSeenVersion],
/// [readOnboardingComplete].
Future<void> maybeShowWhatsNew(
  BuildContext context, {
  String? installedVersionName,
  Future<String?> Function()? readSeenVersion,
  Future<void> Function(String versionName)? writeSeenVersion,
  Future<bool> Function()? readOnboardingComplete,
}) async {
  final installed = installedVersionName ?? AppInfo.versionName;
  try {
    final seen = await (readSeenVersion ?? UpdatePrefs.readWhatsNewSeenVersion)();
    final onboarded = await (readOnboardingComplete ?? AppPrefs.readOnboardingComplete)();
    final show = WhatsNewGate.pending(
      seenVersion: seen,
      installedVersionName: installed,
      onboardingComplete: onboarded,
      hasContentFor: hasWhatsNewContentFor,
    );
    if (!show || !context.mounted) return;
    final choice = await showWhatsNewDialog(context);
    await (writeSeenVersion ?? UpdatePrefs.writeWhatsNewSeenVersion)(installed);
    if (choice == WhatsNewChoice.openBackup && context.mounted) {
      await Navigator.of(context).pushNamed(Routes.backup);
    }
  } catch (_) {}
}
