import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../data/prefs/app_prefs.dart';
import '../../data/prefs/update_prefs.dart';
import '../../domain/whats_new/whats_new_gate.dart';
import '../shell/routes.dart';
import '../startup_notice.dart';
import 'whats_new_content.dart';
import 'whats_new_pager.dart';

/// §UI.WHATSNEW.HOOK — Home's hook (B31, rewritten in 0.1.2 S11a): reads the
/// stored version and the onboarding flag, asks [WhatsNewGate], and shows the
/// pager once per process. Only "Got it" writes the installed version (not
/// awaited, 2 s timeout, a failed write leaves it unseen silently); closing on
/// the first card marks nothing, so the pop-up comes back at the next Home
/// start. Never throws.
///
/// Edge cases: no second pager when Home starts twice in one process; no pager
/// on top of the start-up notice of an unfinished Reset app (it comes back at
/// the next start); a fresh install never gets the pop-up (Welcome marks the
/// version seen).
///
/// Test seams: [installedVersionName], [readSeenVersion], [writeSeenVersion],
/// [readOnboardingComplete], [startupNoticeShown], [openSettings], [openBackup].
Future<void> maybeShowWhatsNew(
  BuildContext context, {
  String? installedVersionName,
  Future<String?> Function()? readSeenVersion,
  Future<void> Function(String versionName)? writeSeenVersion,
  Future<bool> Function()? readOnboardingComplete,
  bool Function()? startupNoticeShown,
  VoidCallback? openSettings,
  VoidCallback? openBackup,
}) async {
  final installed = installedVersionName ?? AppInfo.versionName;
  try {
    if (WhatsNewProcess.autoShown || WhatsNewProcess.isOpen) return;
    final seen = await (readSeenVersion ?? UpdatePrefs.readWhatsNewSeenVersion)();
    final onboarded = await (readOnboardingComplete ?? AppPrefs.readOnboardingComplete)();
    final show = WhatsNewGate.pending(
      seenVersion: seen,
      installedVersionName: installed,
      onboardingComplete: onboarded,
      hasContentFor: hasWhatsNewContentFor,
    );
    if (!show || !context.mounted) return;
    if ((startupNoticeShown ?? () => StartupNotice.shown)()) return;
    if (WhatsNewProcess.autoShown || WhatsNewProcess.isOpen) return;
    WhatsNewProcess.autoShown = true;
    final gotIt = await showWhatsNewPager(
      context,
      onOpenSettings: openSettings ?? () => _push(context, Routes.settings),
      onOpenBackup: openBackup ?? () => _push(context, Routes.backup),
    );
    if (gotIt) {
      WhatsNewProcess.pillCleared = true;
      writeSeenQuietly(
        writeSeenVersion ?? (v) async => await UpdatePrefs.writeWhatsNewSeenVersion(v),
        installed,
      );
    }
  } catch (_) {}
}

void _push(BuildContext context, String route) {
  if (context.mounted) Navigator.of(context).pushNamed(route);
}
