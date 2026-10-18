/// §AUTOREAD.BRIDGE_CHANNEL — the real Dart side of the `app.mmogo/autoread`
/// channel (contract: interface-K4-bridge-channel.md).
///
/// This is the ONLY place the channel name may be spelled in Dart. The raw SMS
/// body is never logged, printed, put in an exception or kept in a field.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../model/waiting_item.dart' show isValidHeldId;
import 'autoread_bridge.dart';

/// A channel failure. Carries only the code (`bad_id`, `not_available`,
/// `permission`, `failed`); never the platform message or any argument.
class AutoReadBridgeException implements Exception {
  final String code;
  const AutoReadBridgeException(this.code);

  @override
  String toString() => 'AutoReadBridgeException($code)';
}

class AutoReadState {
  final bool enabled;
  final bool smsGranted;
  final bool notifGranted;
  final int heldCount;

  const AutoReadState({
    required this.enabled,
    required this.smsGranted,
    required this.notifGranted,
    required this.heldCount,
  });

  @override
  String toString() =>
      'AutoReadState(enabled: $enabled, sms: $smsGranted, notif: $notifGranted, held: $heldCount)';
}

class AutoReadPermissions {
  final bool smsGranted;
  final bool notifGranted;

  const AutoReadPermissions({required this.smsGranted, required this.notifGranted});

  @override
  String toString() => 'AutoReadPermissions(sms: $smsGranted, notif: $notifGranted)';
}

class MethodChannelAutoReadBridge implements AutoReadBridge {
  final Future<int> Function() _generation;
  final MethodChannel _channel;
  final StreamController<String> _tapped = StreamController<String>.broadcast();

  MethodChannelAutoReadBridge({
    required Future<int> Function() generation,
    MethodChannel? channel,
  })  : _generation = generation,
        _channel = channel ?? const MethodChannel('app.mmogo/autoread') {
    if (channel == null) {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  /// Pushed taps (`onTapped`), valid ids only. Broadcast: ids nobody listens
  /// to are dropped, not buffered.
  Stream<String> get tapped => _tapped.stream;

  /// Handles pushed calls. Unknown methods are ignored.
  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'onTapped') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final id = args['id'];
    if (id is String && isValidHeldId(id) && _tapped.hasListener) {
      _tapped.add(id);
    }
    return null;
  }

  Future<dynamic> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<dynamic>(method, args);
    } on PlatformException catch (e) {
      throw AutoReadBridgeException(e.code);
    } on MissingPluginException {
      throw const AutoReadBridgeException('not_available');
    }
  }

  @override
  Future<HeldMessage?> peekHeld(String id) async {
    if (!isValidHeldId(id)) return null;
    final r = await _invoke('peekHeld', {'id': id});
    if (r is! Map) return null;
    final rid = r['id'];
    final body = r['body'];
    final at = r['receivedAtMs'];
    if (rid is! String || rid != id || body is! String || at is! int) return null;
    return HeldMessage(
      id: rid,
      body: body,
      heldAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  @override
  Future<bool> claim(String id) async {
    if (!isValidHeldId(id)) return false;
    final r = await _invoke('claim', {'id': id});
    return r == true;
  }

  @override
  Future<void> release(String id) async {
    if (!isValidHeldId(id)) return;
    await _invoke('release', {'id': id});
  }

  @override
  Future<void> ackHeld(String id, {required int generation}) async {
    if (!isValidHeldId(id)) return;
    await _invoke('ackHeld', {'id': id, 'generation': generation});
  }

  @override
  Future<List<String>> listHeldIds() async {
    final r = await _invoke('listHeldIds');
    if (r is! List) return const [];
    return [
      for (final e in r)
        if (e is String && isValidHeldId(e)) e,
    ];
  }

  /// Not a channel call: the counter lives in Flutter preferences (Dart-owned).
  @override
  Future<int> readGeneration() => _generation();

  Future<AutoReadState> getState() async {
    final r = await _invoke('getState');
    if (r is Map) {
      final e = r['enabled'], s = r['smsGranted'], n = r['notifGranted'], h = r['heldCount'];
      if (e is bool && s is bool && n is bool && h is int) {
        return AutoReadState(enabled: e, smsGranted: s, notifGranted: n, heldCount: h);
      }
    }
    throw const AutoReadBridgeException('failed');
  }

  Future<bool> setEnabled(bool enabled) async {
    final r = await _invoke('setEnabled', {'enabled': enabled});
    if (r is bool) return r;
    throw const AutoReadBridgeException('failed');
  }

  Future<AutoReadPermissions> requestPermissions() async {
    final r = await _invoke('requestPermissions');
    if (r is Map) {
      final s = r['smsGranted'], n = r['notifGranted'];
      if (s is bool && n is bool) {
        return AutoReadPermissions(smsGranted: s, notifGranted: n);
      }
    }
    throw const AutoReadBridgeException('failed');
  }

  /// The held id from the launching intent, once; null when none or invalid.
  Future<String?> takeLaunchId() async {
    final r = await _invoke('takeLaunchId');
    return (r is String && isValidHeldId(r)) ? r : null;
  }

  Future<void> deleteAllHeld() async {
    await _invoke('deleteAllHeld');
  }

  Future<void> openAppSettings() async {
    await _invoke('openAppSettings');
  }
}
