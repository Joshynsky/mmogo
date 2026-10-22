@Tags(['autoread'])
library;

// F8: the phone-notification deep link. Cold start id (once), tapped ids,
// malformed ids ignored, ready or unreadable -> Parse, parsed -> Categorize,
// gone or unknown -> Categorize, the row id handed on, and a tap before Home
// waits for Home. No message content is involved: ids only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/launch_router.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/shell/routes.dart';

import '../../support/waiting_fakes.dart';

class _Source implements AutoReadLaunchSource {
  _Source(this.launchId);
  String? launchId;
  int takeCalls = 0;
  final StreamController<String> taps = StreamController<String>.broadcast();

  @override
  Future<String?> takeLaunchId() async {
    takeCalls++;
    final id = launchId;
    launchId = null; // consumed once, like the real bridge
    return id;
  }

  @override
  Stream<String> get tapped => taps.stream;
}

final DateTime _now = DateTime(2026, 10, 19, 10);

class _Harness {
  _Harness(this.source, this.router, this.opened, this.focus);
  final _Source source;
  final AutoReadLaunchRouter router;
  final List<NotifChip> opened;
  final List<String?> focus;
}

Future<_Harness> _pump(
  WidgetTester t, {
  String? launchId,
  List<WaitingItem> items = const [],
  String initial = Routes.home,
}) async {
  final source = _Source(launchId);
  final key = GlobalKey<NavigatorState>();
  final repo = FakeAutoReadWaitingRepository(items, now: () => _now);
  final router = AutoReadLaunchRouter(source: source, navigatorKey: key, waiting: repo, now: () => _now);
  final opened = <NotifChip>[];
  final focus = <String?>[];
  addTearDown(() {
    router.dispose();
    source.taps.close();
  });
  await t.pumpWidget(MaterialApp(
    navigatorKey: key,
    navigatorObservers: [router.observer],
    initialRoute: initial,
    onGenerateRoute: (s) {
      if (s.name == Routes.notifications) {
        final a = s.arguments;
        opened.add(a is NotificationsRouteArgs ? a.chip : NotifChip.all);
        focus.add(a is NotificationsRouteArgs ? a.focusId : null);
      }
      return MaterialPageRoute<void>(settings: s, builder: (_) => Scaffold(body: Text('page ${s.name}')));
    },
  ));
  await t.pump();
  return _Harness(source, router, opened, focus);
}

WaitingItem _item(int n, WaitingKind k, {int ageHours = 2}) =>
    WaitingItem(id: heldIdFor(n), kind: k, heldAt: _now.subtract(Duration(hours: ageHours)));

WaitingItem _parsed(int n) => WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _now.subtract(const Duration(hours: 2)),
      parsed: sampleFields(n, _now));

void main() {
  testWidgets('cold start id opens Notifications on Categorize, and the id is read once', (t) async {
    final h = await _pump(t, launchId: heldIdFor(1));
    unawaited(h.router.start());
    unawaited(h.router.start()); // a second start does nothing
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.categorize]);
    expect(h.source.takeCalls, 1);
  });

  testWidgets('no launch id: nothing opens', (t) async {
    final h = await _pump(t);
    unawaited(h.router.start());
    await t.pumpAndSettle();
    expect(h.opened, isEmpty);
  });

  testWidgets('every tapped id opens the page (Categorize)', (t) async {
    final h = await _pump(t);
    unawaited(h.router.start());
    h.source.taps.add(heldIdFor(2));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(3));
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.categorize, NotifChip.categorize]);
  });

  testWidgets('ready and unreadable land on Parse, parsed on Categorize; gone and unknown on Categorize', (t) async {
    final h = await _pump(t, items: [
      _item(1, WaitingKind.unreadable),
      _item(2, WaitingKind.gone),
      _item(3, WaitingKind.readyToParse),
      _parsed(4),
    ]);
    unawaited(h.router.start());
    h.source.taps.add(heldIdFor(1));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(2));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(3));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(4));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(99));
    await t.pumpAndSettle();
    expect(h.opened, [
      NotifChip.parse,
      NotifChip.categorize,
      NotifChip.parse,
      NotifChip.categorize,
      NotifChip.categorize,
    ]);
    // The row id goes with the tap only when the item is listed and not gone.
    expect(h.focus, [heldIdFor(1), null, heldIdFor(3), heldIdFor(4), null]);
  });

  testWidgets('a held message ready to parse: Parse chip with its row in focus (warm tap)', (t) async {
    final h = await _pump(t, items: [_item(5, WaitingKind.readyToParse)]);
    unawaited(h.router.start());
    h.source.taps.add(heldIdFor(5));
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.parse]);
    expect(h.focus, [heldIdFor(5)]);
  });

  testWidgets('a held message past the window counts as gone: Categorize, no row', (t) async {
    final h = await _pump(t, items: [_item(6, WaitingKind.readyToParse, ageHours: 200)]);
    unawaited(h.router.start());
    h.source.taps.add(heldIdFor(6));
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.categorize]);
    expect(h.focus, [null]);
  });

  testWidgets('cold start: ready message waits for Home, then Parse with its row in focus', (t) async {
    final h = await _pump(t,
        launchId: heldIdFor(7), items: [_item(7, WaitingKind.readyToParse)], initial: Routes.welcome);
    unawaited(h.router.start());
    await t.pumpAndSettle();
    expect(h.opened, isEmpty);
    t.state<NavigatorState>(find.byType(Navigator)).pushReplacementNamed(Routes.home);
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.parse]);
    expect(h.focus, [heldIdFor(7)]);
  });

  testWidgets('a malformed id never reaches the page as a row id', (t) async {
    final h = await _pump(t, items: [_item(8, WaitingKind.readyToParse)]);
    unawaited(h.router.start());
    h.source.taps.add('${heldIdFor(8)}x');
    h.source.taps.add(heldIdFor(0xabc).toUpperCase());
    await t.pumpAndSettle();
    expect(h.opened, isEmpty);
    expect(h.focus, isEmpty);
  });

  testWidgets('malformed ids are ignored (launch and tap)', (t) async {
    final h = await _pump(t, launchId: 'NOT-A-HELD-ID');
    unawaited(h.router.start());
    for (final bad in ['', 'abc', 'ABCDEF0123456789ABCDEF0123456789', '${heldIdFor(1)}0', '../../etc/passwd']) {
      h.source.taps.add(bad);
    }
    await t.pumpAndSettle();
    expect(h.opened, isEmpty);
  });

  testWidgets('a cold-start tap while still on Welcome waits for Home, and is not replaced by it', (t) async {
    final h = await _pump(t, launchId: heldIdFor(1), initial: Routes.welcome);
    unawaited(h.router.start());
    await t.pumpAndSettle();
    expect(h.opened, isEmpty, reason: 'Welcome is still showing');
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.pushReplacementNamed(Routes.home);
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.categorize]);
    expect(find.text('page ${Routes.notifications}'), findsOneWidget);
  });
}
