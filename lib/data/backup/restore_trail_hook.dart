import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../maintenance/device_keys.dart' show kAirtimeTrailPrefsKey;

/// §DATA.RESTORE.TRAIL_HOOK - what a REPLACE restore does about the 24 h
/// "Recorded automatically" trail: the stored list (row numbers and times)
/// goes, and so does the list in memory, because the rows it pointed at were
/// just replaced. Runs only AFTER a successful commit (never on a failed or
/// rolled-back restore). A Merge restore does not call this: it never deletes a
/// row, so every entry stays true.
///
/// Never throws: a failure here must not undo or fail a restore that already
/// committed (the display also hides any entry whose row is gone).
class AirtimeTrailRestoreHook {
  AirtimeTrailRestoreHook._();

  /// Set by the auto-read app: clears the in-memory list. Null in the standard
  /// build (there is no list).
  static void Function()? clearMemory;

  static const _timeout = Duration(seconds: 2);

  static Future<void> afterReplace() async {
    try {
      final p = await SharedPreferences.getInstance().timeout(_timeout);
      await p.remove(kAirtimeTrailPrefsKey).timeout(_timeout);
    } catch (_) {
      // Left as it was; the display hides entries whose row is gone.
    }
    try {
      clearMemory?.call();
    } catch (_) {}
  }
}
