// Fakes for the Read on/off controller tests: a bridge with a call log, an
// in-memory prefs map with failure switches, and a store that only counts
// generation bumps. No platform channel anywhere.
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';

class FakeReadingBridge implements ReadingBridge {
  FakeReadingBridge({
    this.enabled = false,
    this.smsGranted = false,
    this.notifGranted = false,
    this.heldCount = 0,
    this.parseOn = false,
    this.autostartHelp = false,
  });

  /// The "Parse from the notification" switch (Kotlin prefs) and whether Kotlin
  /// says this is a Xiaomi-family phone.
  bool parseOn;
  bool autostartHelp;

  /// The consent version Kotlin holds (0 = none). Like the real side, it keeps
  /// only its own current version.
  int kotlinConsent = 0;
  Object? setConsentError;
  bool setParseIgnored = false;

  bool enabled;
  bool smsGranted;
  bool notifGranted;
  int heldCount;

  /// What the (pretend) user grants when the system dialog runs.
  bool grantSms = true;
  bool grantNotif = true;

  /// Failure switches.
  Object? requestError;
  Object? setEnabledError;
  Object? stateError;
  bool setEnabledIgnoresOff = false;
  bool deleteHeldKeepsMessages = false;

  final List<String> calls = [];

  @override
  Future<AutoReadState> getState() async {
    calls.add('getState');
    if (stateError != null) throw stateError!;
    return AutoReadState(
      enabled: enabled,
      smsGranted: smsGranted,
      notifGranted: notifGranted,
      heldCount: heldCount,
      parseOn: parseOn,
      autostartHelp: autostartHelp,
      consentVersion: kotlinConsent,
    );
  }

  @override
  Future<bool> setConsent(int version) async {
    calls.add('setConsent:$version');
    if (setConsentError != null) throw setConsentError!;
    if (version == kReadingConsentVersion) kotlinConsent = version;
    return kotlinConsent == kReadingConsentVersion;
  }

  @override
  Future<bool> setParseOn(bool on) async {
    calls.add('setParseOn:$on');
    if (!setParseIgnored) parseOn = on;
    return parseOn;
  }

  @override
  Future<void> openAutostartSettings() async {
    calls.add('openAutostartSettings');
  }

  @override
  Future<AutoReadPermissions> requestPermissions() async {
    calls.add('requestPermissions');
    if (requestError != null) throw requestError!;
    if (grantSms) smsGranted = true;
    if (grantNotif) notifGranted = true;
    return AutoReadPermissions(smsGranted: smsGranted, notifGranted: notifGranted);
  }

  @override
  Future<bool> setEnabled(bool value) async {
    calls.add('setEnabled:$value');
    if (setEnabledError != null) throw setEnabledError!;
    if (!value && setEnabledIgnoresOff) return enabled;
    enabled = value;
    return enabled;
  }

  @override
  Future<void> deleteAllHeld() async {
    calls.add('deleteAllHeld');
    if (!deleteHeldKeepsMessages) heldCount = 0;
  }

  @override
  Future<void> openAppSettings() async {
    calls.add('openAppSettings');
  }
}

class FakeReadingPrefs implements ReadingPrefs {
  final Map<String, Object> data = {};
  bool failRemove = false;
  bool failWrite = false;

  @override
  Future<Set<String>> keys() async => data.keys.toSet();
  @override
  Future<bool> remove(String key) async {
    if (failRemove) return false;
    data.remove(key);
    return true;
  }

  @override
  Future<int?> readInt(String key) async => data[key] as int?;
  @override
  Future<bool> writeInt(String key, int value) async {
    if (failWrite) return false;
    data[key] = value;
    return true;
  }
}

/// Only the generation methods are used by the controller.
class FakeGenerationStore implements PendingItemsStore {
  int generation = 1;
  int bumps = 0;
  bool failBump = false;

  @override
  Future<int> readGeneration() async => generation;
  @override
  Future<int> bumpGeneration() async {
    if (failBump) throw StateError('bump');
    bumps++;
    return ++generation;
  }

  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) => throw UnimplementedError();
  @override
  Future<List<WaitingItem>> list() => throw UnimplementedError();
  @override
  Future<void> remove(String id) => throw UnimplementedError();
  @override
  Future<bool> containsCode(String displayCode) => throw UnimplementedError();
  @override
  Future<int> count() => throw UnimplementedError();
}

String pendingKey(int n) => 'autoread_pending_v1.${n.toRadixString(16).padLeft(32, '0')}';
