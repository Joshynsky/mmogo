import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Real defect found and fixed live, this dispatch (T9): a bare
/// `SharedPreferences.getInstance()` call can hang indefinitely rather than
/// throwing (observed running this project's widget tests on Windows,
/// where `shared_preferences_windows` is the selected federated
/// implementation) — the existing `try/catch` in every method below only
/// helps once the Future actually completes (successfully or with an
/// error); it does nothing for a call that never completes at all. Every
/// `SharedPreferences.getInstance()` call in this file is now wrapped in a
/// bounded `.timeout(...)` so a stuck plugin channel degrades to "treat as
/// unset/failed" instead of hanging the caller (and, in a `testWidgets`
/// test, the whole test) forever. See this dispatch's FLAGS.
const _prefsTimeout = Duration(seconds: 2);

/// Local-device-only preference keys, stored with
/// `shared_preferences` (onboarding flag / hint-seen state /
/// auto-recognize toggle — none of which are this slice's concern) plus
/// the display-name key this slice (T4) newly reads from.
///
/// `keyUserDisplayName` was introduced by T4 as a reader only; T17
/// (Profile) now owns writing it via [AppPrefs.writeUserDisplayName] (the
/// Profile row has an editable display name). Every read
/// here stays defensive: a missing/unset/
/// unreadable value always falls back to `null` (Home's caller then shows
/// the time-of-day greeting with no name, T20), never a thrown exception or an invented default name.
/// Flagged in this dispatch's FLAGS as a naming precedent for T17 to match.
class AppPrefs {
  AppPrefs._();

  static const keyUserDisplayName = 'user_display_name';

  /// T12 — the "Auto-recognize classifications" Settings toggle gate.
  /// Stored in `shared_preferences`, default ON.
  /// T18 (Settings' real switch UI) now owns both the read (already wired
  /// into Add's category chips) and the write (via
  /// [writeAutoRecognizeClassifications]). When OFF,
  /// Add's category chips perform NO lookup at all; writes to
  /// `counterparty_classification_map` are NEVER gated by this flag — see
  /// `CounterpartyDao.upsertOnConfirm`'s own doc comment — so suggestions
  /// resume correctly the moment the toggle is turned back on.
  static const keyAutoRecognizeClassifications =
      'auto_recognize_classifications';

  /// T16 — the onboarding-complete flag (a single boolean, read once
  /// at launch routing). Set only by an
  /// explicit Skip or Get started on the onboarding flow; nothing clears it
  /// except clearing the app's data.
  static const keyOnboardingComplete = 'onboarding_complete';

  /// Read once per launch by the Welcome screen to pick the next route.
  ///
  /// Defensive: any read failure (missing plugin channel, storage error, a
  /// stuck platform call hitting the bounded timeout) fails toward `false`,
  /// i.e. SHOW onboarding. Reasoning: the rule is "onboarding never
  /// auto-skips on its own", and the two failure costs are lopsided — a
  /// returning user who wrongly sees it again loses one tap (Skip, which
  /// saves nothing and changes no data), while a new user who wrongly
  /// skips it never gets the name step or the SMS-paste explanation, with
  /// no way back in. Same fail-toward-showing direction as [readTourSeen].
  static Future<bool> readOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      return prefs.getBool(keyOnboardingComplete) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marks onboarding done (Skip / Get started). Returns whether the write
  /// actually happened; callers still proceed to Home on `false` (never
  /// trap the user on onboarding over a storage failure) — the only cost is
  /// that onboarding shows again next launch, per [readOnboardingComplete].
  static Future<bool> writeOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      return await prefs
          .setBool(keyOnboardingComplete, true)
          .timeout(_prefsTimeout);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readUserDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final value = prefs.getString(keyUserDisplayName);
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } catch (_) {
      // Defensive: plugin channel unavailable, storage read failure, a
      // stuck platform call that never completes, etc. Home must never
      // crash (or hang) over a missing/failed preference read.
      return null;
    }
  }

  /// Maximum display-name length — 30 characters on Profile's name field. Enforced by
  /// the text field; [writeUserDisplayName] does not truncate on its own.
  static const userDisplayNameMaxLength = 30;

  /// Bumped after every successful [writeUserDisplayName]. T17 (Profile)
  /// is the first writer of [keyUserDisplayName], but Home (T4) only read
  /// it once at `initState` — and Profile is pushed ON TOP of a live Home
  /// (or of any primary screen that may itself sit above Home), so on back
  /// Home would still show the old greeting until relaunch. Home listens to
  /// this notifier and simply re-runs [readUserDisplayName] when it fires
  /// (the pref stays the single source of truth; the notifier carries no
  /// value of its own). Any later writer (T16's optional onboarding name
  /// step) gets Home-refresh for free by going through
  /// [writeUserDisplayName] too.
  static final ValueNotifier<int> userDisplayNameRevision = ValueNotifier<int>(
    0,
  );

  /// T17 — persists Profile's "How Home greets you" field. [name] is
  /// trimmed; `null`, empty or whitespace-only REMOVES the key entirely
  /// (never stores `""`), so [readUserDisplayName] returns `null` and Home
  /// greets without a name (T20; was "Welcome back") — the prototype's own `saveName()` rule.
  ///
  /// Same defensive shape as every other writer in this file (bounded
  /// `.timeout`, swallow on failure — never crash the caller), except that
  /// it reports success as a `bool` so Profile's confirmation SnackBar can
  /// say "Saved" only when the write actually happened, rather than
  /// claiming success over a swallowed failure. On success it bumps
  /// [userDisplayNameRevision] so a live Home refreshes its greeting.
  static Future<bool> writeUserDisplayName(String? name) async {
    final trimmed = name?.trim() ?? '';
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final ok = trimmed.isEmpty
          ? await prefs.remove(keyUserDisplayName).timeout(_prefsTimeout)
          : await prefs
                .setString(keyUserDisplayName, trimmed)
                .timeout(_prefsTimeout);
      if (ok) userDisplayNameRevision.value++;
      return ok;
    } catch (_) {
      // Defensive: see doc comment above.
      return false;
    }
  }

  /// Coach-tour "seen" flag, one per page (`tour_seen_<pageId>`).
  static const _tourSeenPrefix = 'tour_seen_';

  /// Whether the page's coach tour has been finished or skipped. Defensive:
  /// any read failure fails toward `false` (show the tour): worst case a
  /// tour reappears once.
  static Future<bool> readTourSeen(String pageId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      return prefs.getBool('$_tourSeenPrefix$pageId') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markTourSeen(String pageId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setBool('$_tourSeenPrefix$pageId', true);
    } catch (_) {
      // Defensive: worst case the tour shows once more.
    }
  }

  /// Settings' "Show tips again": clears every `tour_seen_*` flag.
  static Future<void> resetAllTours() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith(_tourSeenPrefix))
          .toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {
      // Defensive: see [markTourSeen].
    }
  }

  /// Whether the Suggestion-pill lookup should run at all. Defensive: any
  /// read failure (missing plugin channel, stuck platform call, etc.)
  /// fails toward the documented default (ON/true) rather than silently
  /// disabling a feature the user never actually turned off — same
  /// fail-toward-the-safer-direction discipline [readTourSeen] already
  /// uses, applied to this key's own correct default instead of `false`.
  static Future<bool> readAutoRecognizeClassifications() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      return prefs.getBool(keyAutoRecognizeClassifications) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// T18 — persists the Settings screen's "Auto-recognize classifications"
  /// switch. Same defensive shape as [writeCaptureIdentityPreference]: a
  /// failed/stuck write just means the toggle may not stick for the next
  /// app launch (it already reverted in the UI's local state check, or the
  /// user can retry the switch) — never crash the Settings screen over it.
  static Future<void> writeAutoRecognizeClassifications(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setBool(keyAutoRecognizeClassifications, value);
    } catch (_) {
      // Defensive: see doc comment above.
    }
  }

  /// T6 return-pass-2, D3 (M-Pesa entry rules settled by the PM,
  /// 2026-09-19) — the Add — M-Pesa tab's "Also record
  /// receiver's name & phone / business & account / merchant" opt-in
  /// capture checkbox is a REMEMBERED preference across all three
  /// transaction types, not a per-entry default that resets: read on
  /// entry, defaults to ticked (true) the first time, saved every time the
  /// user manually toggles it. A parse never writes this key — only an
  /// explicit user tap does. Defensive: any read failure fails toward the
  /// documented default (ON/true), same discipline
  /// [readAutoRecognizeClassifications] already uses for its own correct
  /// default.
  static const keyCaptureIdentityPreference = 'capture_identity_preference';

  static Future<bool> readCaptureIdentityPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      return prefs.getBool(keyCaptureIdentityPreference) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> writeCaptureIdentityPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setBool(keyCaptureIdentityPreference, value);
    } catch (_) {
      // Defensive: a failed/stuck write just means the preference may not
      // stick for the next entry — never crash the form dismissing it.
    }
  }

  /// T23 — the chosen colour palette (`ocean` | `leaf` | `indigo`;
  /// `AppPalettes`), read once at startup by `AppPaletteController.load`
  /// and written on every tap of a Settings palette tile. Kept as a plain
  /// string set here (not importing the UI theme layer, which is the one
  /// direction this project's dependencies run) rather than reusing
  /// `AppPalettes.all`'s ids.
  static const keyPaletteId = 'palette_id';
  static const _validPaletteIds = {'ocean', 'leaf', 'indigo'};

  /// Defensive: any read failure, or a missing/unrecognised stored value
  /// (a corrupt write, or an id from a since-removed palette), falls back
  /// to `ocean` — the documented default (T23 scope rule).
  static Future<String> readPaletteId() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final id = prefs.getString(keyPaletteId);
      return _validPaletteIds.contains(id) ? id! : 'ocean';
    } catch (_) {
      return 'ocean';
    }
  }

  static Future<void> writePaletteId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setString(keyPaletteId, id);
    } catch (_) {
      // Defensive: a failed/stuck write just means the choice may not
      // stick for the next launch — never crash the tap applying it.
    }
  }
}
