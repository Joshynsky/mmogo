@Tags(['autoread'])
library;

// 0.2.1 Ask first: the Change category button of the phone alert opens mmogo straight at the Categorize sheet
// for that item (cold start and running app), a plain tap still only opens To do, and the page opens the
// sheet exactly once, when the row is listed. Ids only; no message content.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/launch_router.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/shell/routes.dart';

import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

class _Source implements AutoReadLaunchSource, CategorizeLaunchSource {
  _Source(this.launchId, {this.launchCategorize = false});
  String? launchId;
  bool launchCategorize;
  final StreamController<String> taps = StreamController<String>.broadcast();
  final StreamController<String> categorize = StreamController<String>.broadcast();

  @override
  Future<String?> takeLaunchId() async {
    final id = launchId;
    launchId = null;
    return id;
  }

  @override
  Future<bool> takeLaunchCategorize() async {
    final c = launchCategorize;
    launchCategorize = false;
    return c;
  }

  @override
  Stream<String> get tapped => taps.stream;

  @override
  Stream<String> get categorizeTapped => categorize.stream;
}

final DateTime _now = DateTime(2026, 11, 19, 10);

WaitingItem _parsed(int n) => WaitingItem(
    id: heldIdFor(n),
    kind: WaitingKind.waitingCategory,
    heldAt: _now.subtract(const Duration(hours: 2)),
    parsed: sampleFields(n, _now));

void main() {
  late List<NotificationsRouteArgs> opened;

  Future<_Source> pump(WidgetTester t, _Source source, List<WaitingItem> items) async {
    opened = [];
    final key = GlobalKey<NavigatorState>();
    final router = AutoReadLaunchRouter(
        source: source, navigatorKey: key, waiting: FakeAutoReadWaitingRepository(items, now: () => _now), now: () => _now);
    addTearDown(() {
      router.dispose();
      source.taps.close();
      source.categorize.close();
    });
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [router.observer],
      initialRoute: Routes.home,
      onGenerateRoute: (s) {
        final a = s.arguments;
        if (s.name == Routes.notifications && a is NotificationsRouteArgs) opened.add(a);
        return MaterialPageRoute<void>(settings: s, builder: (_) => const Scaffold(body: SizedBox()));
      },
    ));
    await t.pump();
    unawaited(router.start());
    await t.pumpAndSettle();
    return source;
  }

  testWidgets('cold start from Change category: To do, the row, and the sheet to open for that id', (t) async {
    await pump(t, _Source(heldIdFor(4), launchCategorize: true), [_parsed(4)]);
    expect(opened.single.focusId, heldIdFor(4));
    expect(opened.single.openCategorizeId, heldIdFor(4));
  });

  testWidgets('cold start from a plain tap: no sheet', (t) async {
    await pump(t, _Source(heldIdFor(4)), [_parsed(4)]);
    expect(opened.single.openCategorizeId, isNull);
  });

  testWidgets('running app: the id is announced as a Change category tap BEFORE the tap, and only that tap opens the sheet', (t) async {
    final s = await pump(t, _Source(null), [_parsed(4), _parsed(5)]);
    s.categorize.add(heldIdFor(4));
    s.taps.add(heldIdFor(4));
    await t.pumpAndSettle();
    s.taps.add(heldIdFor(5)); // a plain tap on another row
    await t.pumpAndSettle();
    expect(opened.map((a) => a.openCategorizeId), [heldIdFor(4), null]);
  });

  testWidgets('a Change category tap on an item that is gone opens To do with no row and no sheet', (t) async {
    await pump(t, _Source(heldIdFor(9), launchCategorize: true), const []);
    expect(opened.single.focusId, isNull);
    expect(opened.single.openCategorizeId, isNull);
  });

  testWidgets('a launch source without the button (older or fake) still works', (t) async {
    // A plain AutoReadLaunchSource only: the router must not need the extra interface.
    final plain = _PlainSource(heldIdFor(4));
    opened = [];
    final key = GlobalKey<NavigatorState>();
    final router = AutoReadLaunchRouter(
        source: plain, navigatorKey: key, waiting: FakeAutoReadWaitingRepository([_parsed(4)], now: () => _now), now: () => _now);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [router.observer],
      initialRoute: Routes.home,
      onGenerateRoute: (s) {
        final a = s.arguments;
        if (s.name == Routes.notifications && a is NotificationsRouteArgs) opened.add(a);
        return MaterialPageRoute<void>(settings: s, builder: (_) => const Scaffold(body: SizedBox()));
      },
    ));
    await t.pump();
    unawaited(router.start());
    await t.pumpAndSettle();
    expect(opened.single.focusId, heldIdFor(4));
    expect(opened.single.openCategorizeId, isNull);
  });

  group('the page opens the Categorize sheet once', () {
    final skip = !kAutoReadCompiled;

    Future<List<String>> open(WidgetTester t, {String? openId, List<WaitingItem>? items}) async {
      final calls = <String>[];
      await t.pumpWidget(MaterialApp(
        home: NotificationsPage(
          news: FakeNotificationsRepository(const []),
          waiting: FakeAutoReadWaitingRepository(items ?? [_parsed(1), _parsed(2)], now: () => _now),
          clock: () => _now,
          openCategorizeId: openId,
          waitingActions: WaitingActions(onCategorize: (i) => calls.add(i.id)),
        ),
      ));
      await t.pump();
      await t.pump();
      return calls;
    }

    testWidgets('the named row only, once', (t) async {
      final calls = await open(t, openId: heldIdFor(2));
      expect(calls, [heldIdFor(2)]);
    }, skip: skip);

    testWidgets('no id: the sheet never opens by itself', (t) async {
      expect(await open(t), isEmpty);
    }, skip: skip);

    testWidgets('an id that is not listed opens nothing', (t) async {
      expect(await open(t, openId: heldIdFor(9)), isEmpty);
    }, skip: skip);
  });
}

class _PlainSource implements AutoReadLaunchSource {
  _PlainSource(this.id);
  String? id;
  @override
  Future<String?> takeLaunchId() async {
    final r = id;
    id = null;
    return r;
  }

  @override
  Stream<String> get tapped => const Stream<String>.empty();
}
