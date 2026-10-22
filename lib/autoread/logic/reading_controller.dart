/// §AUTOREAD.READING — the Dart side of the Read on/off switch (FE-N7, AR5).
///
/// Turning ON needs the user's consent (asked by the UI first) and BOTH system
/// permissions, and only then calls `setEnabled(true)`. Turning OFF only stops
/// capture: `setEnabled(false)`. Messages already read or held are KEPT (PM
/// 19-10-2026); Delete held messages and Delete data are the ways to clear.
///
/// No message text is ever read here: the controller sees counts and flags.
/// Autoread flavor only.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/maintenance/device_keys.dart' show kPendingItemKeyPrefix;
import '../bridge/method_channel_autoread_bridge.dart';
import '../data/pending_items_store.dart';

/// The consent decision, kept in the app's preferences. It stores the VERSION
/// of the consent text the user agreed to (an int), so a changed text asks
/// again. Delete data must clear this key (the orchestrator wires that); it
/// must also stay on the never-in-backups list.
const String kReadingConsentKey = 'autoread_consent_version_v1';

/// Bump when the consent text changes in meaning; everyone is asked again.
/// 2 (0.1.2): one consent screen with a switch per consent. The Kotlin side
/// holds the same number (`ConsentGate.CONSENT_VERSION`); a test pins them.
const int kReadingConsentVersion = 2;

/// What the Settings rows need from the platform bridge. The real
/// implementation wraps `MethodChannelAutoReadBridge`; tests use a fake.
abstract class ReadingBridge {
  Future<AutoReadState> getState();
  Future<bool> setEnabled(bool enabled);
  Future<AutoReadPermissions> requestPermissions();
  Future<void> deleteAllHeld();
  Future<void> openAppSettings();

  /// Tells the Kotlin side which consent version the user agreed to. Kotlin
  /// keeps its own copy and accepts only its own current version.
  Future<bool> setConsent(int version);

  /// The "Parse from the notification" switch, kept in the auto-read prefs.
  Future<bool> setParseOn(bool on);

  /// Opens the phone's Autostart screen (Xiaomi family) or, failing that,
  /// the app's own page in Android settings. Never called automatically.
  Future<void> openAutostartSettings();
}

/// The real bridge adapter.
class ChannelReadingBridge implements ReadingBridge {
  ChannelReadingBridge(this._bridge);
  final MethodChannelAutoReadBridge _bridge;

  @override
  Future<AutoReadState> getState() => _bridge.getState();
  @override
  Future<bool> setEnabled(bool enabled) => _bridge.setEnabled(enabled);
  @override
  Future<AutoReadPermissions> requestPermissions() => _bridge.requestPermissions();
  @override
  Future<void> deleteAllHeld() => _bridge.deleteAllHeld();
  @override
  Future<void> openAppSettings() => _bridge.openAppSettings();
  @override
  Future<bool> setConsent(int version) => _bridge.setConsent(version);
  @override
  Future<bool> setParseOn(bool on) => _bridge.setParseOn(on);
  @override
  Future<void> openAutostartSettings() => _bridge.openAutostartSettings();
}

/// The few preference operations the controller needs (fresh reads).
abstract class ReadingPrefs {
  Future<Set<String>> keys();
  Future<bool> remove(String key);
  Future<int?> readInt(String key);
  Future<bool> writeInt(String key, int value);
}

class SharedReadingPrefs implements ReadingPrefs {
  Future<SharedPreferences> _fresh() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  @override
  Future<Set<String>> keys() async => (await _fresh()).getKeys();
  @override
  Future<bool> remove(String key) async => (await _fresh()).remove(key);
  @override
  Future<int?> readInt(String key) async => (await _fresh()).getInt(key);
  @override
  Future<bool> writeInt(String key, int value) async => (await _fresh()).setInt(key, value);
}

/// Why turning on did not finish.
enum Denied {
  /// The SMS permission was not granted.
  sms,

  /// The notifications permission was not granted.
  notifications,

  /// Neither was granted, or the system refused to ask (for example restricted
  /// settings): the help page applies.
  blocked,
}

enum TurnOnOutcome { on, needsConsent, denied, failed }

class TurnOnResult {
  final TurnOnOutcome outcome;
  final Denied? denied;
  const TurnOnResult._(this.outcome, [this.denied]);

  static const on = TurnOnResult._(TurnOnOutcome.on);
  static const needsConsent = TurnOnResult._(TurnOnOutcome.needsConsent);
  static const failed = TurnOnResult._(TurnOnOutcome.failed);
  factory TurnOnResult.denied(Denied d) => TurnOnResult._(TurnOnOutcome.denied, d);

  bool get isOn => outcome == TurnOnOutcome.on;
}

enum TurnOffResult {
  /// Off: no new messages are captured. What was read or held is kept.
  off,

  /// The switch could not be turned off.
  stillOn,
}

/// What the Settings rows show.
class ReadingState {
  final bool available;
  final bool on;
  final bool smsAllowed;
  final bool notificationsAllowed;
  final int heldCount;

  /// The "Parse from the notification" switch (kept on the Kotlin side).
  final bool parseOn;

  /// True on a Xiaomi-family phone (decided in Kotlin): the Autostart row shows.
  final bool autostartHelp;

  const ReadingState({
    required this.available,
    required this.on,
    required this.smsAllowed,
    required this.notificationsAllowed,
    required this.heldCount,
    this.parseOn = false,
    this.autostartHelp = false,
  });

  /// The platform could not be asked: treated as off and not available.
  static const unavailable = ReadingState(
    available: false,
    on: false,
    smsAllowed: false,
    notificationsAllowed: false,
    heldCount: 0,
  );

  /// Read is on but a permission is missing: capture is not working.
  bool get broken => available && on && !(smsAllowed && notificationsAllowed);

  @override
  String toString() =>
      'ReadingState(available: $available, on: $on, sms: $smsAllowed, notif: $notificationsAllowed, held: $heldCount)';
}

class ReadingController {
  ReadingController({
    required ReadingBridge bridge,
    required PendingItemsStore store,
    required ReadingPrefs prefs,
  })  : _bridge = bridge,
        _store = store,
        _prefs = prefs;

  final ReadingBridge _bridge;
  final PendingItemsStore _store;
  final ReadingPrefs _prefs;

  /// The state now. A platform failure answers [ReadingState.unavailable].
  Future<ReadingState> state() async {
    try {
      final s = await _bridge.getState();
      return ReadingState(
        available: true,
        on: s.enabled,
        smsAllowed: s.smsGranted,
        notificationsAllowed: s.notifGranted,
        heldCount: s.heldCount,
        parseOn: s.parseOn,
        autostartHelp: s.autostartHelp,
      );
    } catch (_) {
      return ReadingState.unavailable;
    }
  }

  /// True when the user agreed to the CURRENT consent text. Both sides must hold
  /// the current version: if Kotlin holds a different number (including 0) the
  /// answer is NOT current, so the consent screen is shown again and Allow
  /// stores both (security re-look C1, PM 22-10-2026).
  Future<bool> hasConsent() async {
    try {
      if (await _prefs.readInt(kReadingConsentKey) != kReadingConsentVersion) return false;
      return (await _bridge.getState()).consentVersion == kReadingConsentVersion;
    } catch (_) {
      return false;
    }
  }

  /// Remembers the agreement (Kotlin side first, then the app's preferences);
  /// read back. False when it could not be stored.
  Future<bool> recordConsent() async {
    try {
      if (!await _bridge.setConsent(kReadingConsentVersion)) return false;
      if (!await _prefs.writeInt(kReadingConsentKey, kReadingConsentVersion)) return false;
      return await _prefs.readInt(kReadingConsentKey) == kReadingConsentVersion;
    } catch (_) {
      return false;
    }
  }

  /// Turns Read on. Without consent nothing is asked of the system. The order
  /// is fixed: permissions first, then `setEnabled(true)`, and only when BOTH
  /// are granted. A denial leaves Read off.
  Future<TurnOnResult> turnOn() async {
    if (!await hasConsent()) return TurnOnResult.needsConsent;
    try {
      var s = await _bridge.getState();
      var sms = s.smsGranted;
      var notif = s.notifGranted;
      if (!sms || !notif) {
        final p = await _bridge.requestPermissions();
        sms = p.smsGranted;
        notif = p.notifGranted;
      }
      if (!sms && !notif) return TurnOnResult.denied(Denied.blocked);
      if (!sms) return TurnOnResult.denied(Denied.sms);
      if (!notif) return TurnOnResult.denied(Denied.notifications);
      final now = await _bridge.setEnabled(true);
      return now ? TurnOnResult.on : TurnOnResult.failed;
    } on AutoReadBridgeException catch (e) {
      // The system refused to ask (or the platform said no): help applies.
      return e.code == 'permission' ? TurnOnResult.denied(Denied.blocked) : TurnOnResult.failed;
    } catch (_) {
      return TurnOnResult.failed;
    }
  }

  /// Turns Read off. Nothing is cleared: the waiting and held messages stay.
  Future<TurnOffResult> turnOff() async {
    try {
      return await _bridge.setEnabled(false) ? TurnOffResult.stillOn : TurnOffResult.off;
    } catch (_) {
      return TurnOffResult.stillOn;
    }
  }

  /// Fail closed on every launch and resume (SEC-R M10): the platform switch may
  /// stay on only while the user's consent answer is the CURRENT consent
  /// version. If it is on without that (the text changed, or the answer is
  /// gone, for example after a restore), it is forced off. Held and waiting
  /// messages are kept. True when nothing needed forcing or the force worked;
  /// false when the switch could not be forced off. A missing permission is not
  /// forced: the "Capture is on but not working: fix" row shows it.
  Future<bool> reconcile() async {
    try {
      final s = await _bridge.getState();
      if (!s.enabled) return true;
      if (await hasConsent()) return true;
      return !await _bridge.setEnabled(false);
    } catch (_) {
      return false;
    }
  }

  /// Bump first, then remove every prefixed key, then read back. True only when
  /// the bump took and no prefixed key is left. Used by Delete held messages
  /// (and, in integration, Delete data).
  Future<bool> clearWaiting() async {
    var ok = true;
    try {
      final before = await _store.readGeneration();
      final next = await _store.bumpGeneration();
      if (next <= before) ok = false;
    } catch (_) {
      ok = false;
    }
    try {
      for (final k in (await _prefs.keys()).where((k) => k.startsWith(kPendingItemKeyPrefix))) {
        if (!await _prefs.remove(k)) ok = false;
      }
      if ((await _prefs.keys()).any((k) => k.startsWith(kPendingItemKeyPrefix))) ok = false;
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  Future<bool> _heldIsEmpty() async {
    try {
      return (await _bridge.getState()).heldCount == 0;
    } catch (_) {
      return false;
    }
  }

  /// Removes every held message on the Kotlin side AND the waiting items Dart
  /// keeps for them; true when both read back empty.
  Future<bool> deleteHeld() async {
    try {
      await _bridge.deleteAllHeld();
    } catch (_) {
      await clearWaiting();
      return false;
    }
    final cleared = await clearWaiting();
    return await _heldIsEmpty() && cleared;
  }

  /// Sets the "Parse from the notification" switch. False when it could not be
  /// stored (the switch then reads back as it was).
  Future<bool> setParse(bool on) async {
    try {
      return await _bridge.setParseOn(on) == on;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Autostart screen (or the app's own settings page). False on a
  /// platform error. Only ever called from a button the user taps.
  Future<bool> openAutostartSettings() async {
    try {
      await _bridge.openAutostartSettings();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the app's own page in Android settings. False on a platform error.
  Future<bool> openAppSettings() async {
    try {
      await _bridge.openAppSettings();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Where the app's one controller lives. Integration sets [instance] once at
/// start (it must share the app's ONE channel bridge: a second bridge would
/// replace the channel's pushed-call handler). Null = the Settings rows show
/// nothing.
class ReadingControllerHolder {
  ReadingControllerHolder._();
  static ReadingController? instance;
}
