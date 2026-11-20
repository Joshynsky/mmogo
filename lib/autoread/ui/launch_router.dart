/// §AUTOREAD.LAUNCH_ROUTER — opens the Notifications page when the user taps a
/// phone notification (cold start through `takeLaunchId`, running app through
/// the `tapped` stream; contract `interface-K4-bridge-channel.md`).
///
/// Destination: the To do chip for every listed item (ready to parse,
/// unreadable or already parsed), with that row scrolled into view and no
/// outline (the id goes to the page as focusId). An unknown or gone id opens
/// To do with no row focused.
/// It never reads or shows message content: only the 32-hex id and the item's
/// kind are used, and a malformed id is ignored.
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

/// A launch source that also knows the Change category button of an Ask first alert. The router uses it
/// when the source offers it; a source without it simply never opens the Categorize sheet.
abstract class CategorizeLaunchSource {
  /// True when the launching intent was that button (once).
  Future<bool> takeLaunchCategorize();

  /// Ids among the tapped ids that came from that button; each is announced BEFORE its tapped event.
  Stream<String> get categorizeTapped;
}

/// Adapts the real bridge. The launch id is read from the platform ONCE and the
/// answer is shared by everyone who asks.
class BridgeLaunchSource implements AutoReadLaunchSource, CategorizeLaunchSource {
  BridgeLaunchSource(this._bridge);
  final MethodChannelAutoReadBridge _bridge;
  Future<String?>? _launch;

  @override
  Future<String?> takeLaunchId() => _launch ??= _bridge.takeLaunchId();

  @override
  Stream<String> get tapped => _bridge.tapped;

  Future<bool>? _launchCategorize;

  @override
  Future<bool> takeLaunchCategorize() => _launchCategorize ??= _bridge.takeLaunchCategorize();

  @override
  Stream<String> get categorizeTapped => _bridge.categorizeTapped;
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
  StreamSubscription<String>? _categorizeSub;
  final Set<String> _categorizeIds = {};
  bool _started = false;
  bool _homeShown = false;
  _Target? _pending;

  /// Starts listening and reads the launch id once. A second call does nothing.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final s = source;
    if (s is CategorizeLaunchSource) {
      _categorizeSub = (s as CategorizeLaunchSource).categorizeTapped.listen(_categorizeIds.add, onError: (Object _) {});
    }
    _sub = source.tapped.listen(
      (id) => unawaited(_handle(id)),
      onError: (Object _) {},
    );
    try {
      final s = source;
      final categorize = s is CategorizeLaunchSource && await (s as CategorizeLaunchSource).takeLaunchCategorize();
      final id = await source.takeLaunchId();
      if (id != null) {
        if (categorize) _categorizeIds.add(id);
        await _handle(id);
      }
    } catch (_) {
      // A failed launch read is "no tap".
    }
  }

  void dispose() {
    _sub?.cancel();
    _categorizeSub?.cancel();
  }

  void _onRoute(Route<dynamic>? route) {
    if (route?.settings.name != Routes.home) return;
    _homeShown = true;
    final target = _pending;
    if (target != null) {
      _pending = null;
      Future<void>.microtask(
        () => _open(target),
      ); // not inside the navigator's own callback
    }
  }

  Future<void> _handle(String id) async {
    if (!isValidHeldId(id)) return;
    final categorize = _categorizeIds.remove(id);
    final target = (await _targetFor(id)).withCategorize(categorize);
    if (!_homeShown) {
      _pending = target; // newest tap wins
      return;
    }
    _open(target);
  }

  Future<_Target> _targetFor(String id) async {
    const fallback = _Target(NotifChip.todo, null);
    final repo = waiting;
    if (repo == null) return fallback;
    StreamSubscription<List<WaitingItem>>? sub;
    try {
      final first = Completer<List<WaitingItem>>();
      sub = repo.watch().listen((v) {
        if (!first.isCompleted) first.complete(v);
      }, onError: (Object _) {});
      final items = await first.future.timeout(lookupTimeout);
      for (final i in items) {
        if (i.id == id) {
          return switch (effectiveKind(i, _now())) {
            WaitingKind.readyToParse ||
            WaitingKind.waitingCategory =>
              _Target(NotifChip.todo, id),
            WaitingKind.unreadable || WaitingKind.gone => fallback,
          };
        }
      }
    } catch (_) {
      // No answer in time: To do, no row.
    } finally {
      unawaited(sub?.cancel());
    }
    return fallback;
  }

  void _open(_Target target) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamed(
      Routes.notifications,
      arguments: NotificationsRouteArgs(
        chip: target.chip,
        focusId: target.focusId,
        openCategorizeId: target.categorize ? target.focusId : null,
      ),
    );
  }
}

/// Where a tap goes: the chip, and the row to bring into view (null = none).
class _Target {
  const _Target(this.chip, this.focusId, {this.categorize = false});
  final NotifChip chip;
  final String? focusId;

  /// Open the Categorize sheet for [focusId] (the Change category button). Only meaningful with a row.
  final bool categorize;

  _Target withCategorize(bool on) => on && focusId != null ? _Target(chip, focusId, categorize: true) : this;
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
