import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../data/prefs/app_prefs.dart';
import '../../data/prefs/update_prefs.dart';
import '../../data/updates/updates_inbox.dart';
import '../../data/updates/whats_new_notice.dart';
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
/// When the page is due, the bell also gets its "What's new in mmogo X" item
/// (once per version). "Got it" does NOT mark it read: the bell stays lit until
/// the item is opened from Notifications (PM, 22-10-2026).
///
/// Test seams: [installedVersionName], [readSeenVersion], [writeSeenVersion],
/// [readOnboardingComplete], [startupNoticeShown], [openSettings], [openBackup],
/// [inbox].
Future<void> maybeShowWhatsNew(
  BuildContext context, {
  String? installedVersionName,
  Future<String?> Function()? readSeenVersion,
  Future<void> Function(String versionName)? writeSeenVersion,
  Future<bool> Function()? readOnboardingComplete,
  bool Function()? startupNoticeShown,
  VoidCallback? openSettings,
  VoidCallback? openBackup,
  UpdatesInbox? inbox,
}) async {
  final installed = installedVersionName ?? AppInfo.versionName;
  final box = inbox ?? UpdatesInbox.instance;
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
    if (!show) return;
    unawaited(WhatsNewNotice.addIfDue(box, installed)); // the bell item; never holds the page back
    if (!context.mounted) return;
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

/// Opens the What's-new page to READ (the Updates entry, and its Notifications
/// row): no "Got it", Back only. Opening it is what counts as seen: the NEW
/// pill clears, the installed version is stored as seen and the bell item is
/// marked read. Does nothing while a page is already open. Never throws.
Future<void> openWhatsNewToRead(
  BuildContext context, {
  String? installedVersionName,
  Future<void> Function(String versionName)? writeSeenVersion,
  VoidCallback? openSettings,
  VoidCallback? openBackup,
  UpdatesInbox? inbox,
}) async {
  if (WhatsNewProcess.isOpen) return;
  final installed = installedVersionName ?? AppInfo.versionName;
  try {
    WhatsNewProcess.pillCleared = true;
    writeSeenQuietly(writeSeenVersion ?? (v) async => await UpdatePrefs.writeWhatsNewSeenVersion(v), installed);
    unawaited((inbox ?? UpdatesInbox.instance).markRead(Notice.whatsNewTagFor(installed)));
    if (!context.mounted) return;
    await showWhatsNewPager(
      context,
      readOnly: true,
      onOpenSettings: openSettings ?? () => _push(context, Routes.settings),
      onOpenBackup: openBackup ?? () => _push(context, Routes.backup),
    );
  } catch (_) {}
}

void _push(BuildContext context, String route) {
  if (context.mounted) Navigator.of(context).pushNamed(route);
}
