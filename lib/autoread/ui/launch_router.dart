/// §AUTOREAD.LAUNCH_ROUTER — opens the Notifications page when the user taps a
/// phone notification (cold start through `takeLaunchId`, running app through
/// the `tapped` stream; contract `interface-K4-bridge-channel.md`).
///
/// Stage 1 destination: the Categorize chip; the Parse chip when the item is
/// unreadable. An unknown or gone id goes to Categorize. It never reads or
/// shows message content: only the 32-hex id is used, and a malformed id is
/// ignored.
///
/// A cold start (or a tap while the app is still on Welcome or Onboarding)
/// waits until Home is on screen, because Welcome replaces its own route and
/// would otherwise replace the page. Register [observer] on the app's
/// `navigatorObservers` so it can see that.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/notifications/notif_chip.dart';
import '../../ui/shell/routes.dart';
import '../bridge/method_channel_autoread_bridge.dart';
import 't1_test_host.dart' show BridgeT1Controls;
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';

/// The two bridge calls the router needs. `AutoReadBridge` itself does not
/// carry them yet; [BridgeLaunchSource] adapts the real bridge.
abstract class AutoReadLaunchSource {
  /// The id from the launching intent, once; null when none.
  Future<String?> takeLaunchId();

  /// Ids of notification taps while the app is running.
  Stream<String> get tapped;
}

/// Adapts the real bridge. The launch id is read from the platform ONCE and the
/// answer is shared by everyone who asks (the router and, in a debug build, the
/// T1 test host), so neither steals the id from the other.
class BridgeLaunchSource implements AutoReadLaunchSource {
  BridgeLaunchSource(this._bridge);
  final MethodChannelAutoReadBridge _bridge;
  Future<String?>? _launch;

  @override
  Future<String?> takeLaunchId() => _launch ??= _bridge.takeLaunchId();

  @override
  Stream<String> get tapped => _bridge.tapped;
}

class AutoReadLaunchRouter {
  AutoReadLaunchRouter({
    required this.source,
    required this.navigatorKey,
    this.waiting,
    DateTime Function()? now,
    this.lookupTimeout = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now;

  final AutoReadLaunchSource source;
  final GlobalKey<NavigatorState> navigatorKey;
  final AutoReadWaitingRepository? waiting;
  final DateTime Function() _now;
  final Duration lookupTimeout;

  /// Register on `MaterialApp.navigatorObservers`.
  late final NavigatorObserver observer = _HomeObserver(_onRoute);

  StreamSubscription<String>? _sub;
  bool _started = false;
  bool _homeShown = false;
  NotifChip? _pending;

  /// Starts listening and reads the launch id once. A second call does nothing.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = source.tapped.listen(
      (id) => unawaited(_handle(id)),
      onError: (Object _) {},
    );
    try {
      final id = await source.takeLaunchId();
      if (id != null) await _handle(id);
    } catch (_) {
      // A failed launch read is "no tap".
    }
  }

  void dispose() => _sub?.cancel();

  void _onRoute(Route<dynamic>? route) {
    if (route?.settings.name != Routes.home) return;
    _homeShown = true;
    final chip = _pending;
    if (chip != null) {
      _pending = null;
      Future<void>.microtask(
        () => _open(chip),
      ); // not inside the navigator's own callback
    }
  }

  Future<void> _handle(String id) async {
    if (!isValidHeldId(id)) return;
    final chip = await _chipFor(id);
    if (!_homeShown) {
      _pending = chip; // newest tap wins
      return;
    }
    _open(chip);
  }

  Future<NotifChip> _chipFor(String id) async {
    final repo = waiting;
    if (repo == null) return NotifChip.categorize;
    StreamSubscription<List<WaitingItem>>? sub;
    try {
      final first = Completer<List<WaitingItem>>();
      sub = repo.watch().listen((v) {
        if (!first.isCompleted) first.complete(v);
      }, onError: (Object _) {});
      final items = await first.future.timeout(lookupTimeout);
      for (final i in items) {
        if (i.id == id) {
          return effectiveKind(i, _now()) == WaitingKind.unreadable
              ? NotifChip.parse
              : NotifChip.categorize;
        }
      }
    } catch (_) {
      // No answer in time: Categorize.
    } finally {
      unawaited(sub?.cancel());
    }
    return NotifChip.categorize;
  }

  void _open(NotifChip chip) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamed(
      Routes.notifications,
      arguments: NotificationsRouteArgs(chip: chip),
    );
  }
}

class _HomeObserver extends NavigatorObserver {
  _HomeObserver(this._on);
  final void Function(Route<dynamic>? route) _on;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _on(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _on(newRoute);
}

/// TEMPORARY (goes with the T1 host, removed by the integration slice): the T1
/// test host's controls over the SAME bridge and the shared launch id.
class SharedBridgeT1Controls extends BridgeT1Controls {
  SharedBridgeT1Controls(super.bridge, this._source);
  final AutoReadLaunchSource _source;

  @override
  Future<String?> takeLaunchId() => _source.takeLaunchId();
}
