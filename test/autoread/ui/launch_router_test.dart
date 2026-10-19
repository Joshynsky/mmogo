@Tags(['autoread'])
library;

// F8: the phone-notification deep link. Cold start id (once), tapped ids,
// malformed ids ignored, unreadable -> Parse, unknown -> Categorize, and a tap
// before Home waits for Home. No message content is involved: ids only.
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
  _Harness(this.source, this.router, this.opened);
  final _Source source;
  final AutoReadLaunchRouter router;
  final List<NotifChip> opened;
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
      }
      return MaterialPageRoute<void>(settings: s, builder: (_) => Scaffold(body: Text('page ${s.name}')));
    },
  ));
  await t.pump();
  return _Harness(source, router, opened);
}

WaitingItem _item(int n, WaitingKind k, {int ageHours = 2}) =>
    WaitingItem(id: heldIdFor(n), kind: k, heldAt: _now.subtract(Duration(hours: ageHours)));

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

  testWidgets('an unreadable item lands on Parse; unknown and gone ids on Categorize', (t) async {
    final h = await _pump(t, items: [
      _item(1, WaitingKind.unreadable),
      _item(2, WaitingKind.gone),
      _item(3, WaitingKind.readyToParse),
    ]);
    unawaited(h.router.start());
    h.source.taps.add(heldIdFor(1));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(2));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(3));
    await t.pumpAndSettle();
    h.source.taps.add(heldIdFor(99));
    await t.pumpAndSettle();
    expect(h.opened, [NotifChip.parse, NotifChip.categorize, NotifChip.categorize, NotifChip.categorize]);
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
