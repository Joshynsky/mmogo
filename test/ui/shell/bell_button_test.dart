// F8: the bell in the top bar (four icon states from the counts, spoken
// labels, the tap goes to the Notifications page on the All chip), the counts
// tracker and the inbox adapter. Runs in both flavors: pill and diamond
// checks are made only when auto-read is compiled in.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/ui/shell/bell_button.dart';
import 'package:mmogo/ui/shell/bell_counts.dart';
import 'package:mmogo/ui/shell/notifications_scope.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/shell/updates_news_repository.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/news_fakes.dart';

Finder _shape(NotifShape s) => find.byWidgetPredicate((w) => w is NotifShapeIcon && w.shape == s);

Future<ValueNotifier<BellCounts>> _pump(WidgetTester t, BellCounts c) async {
  final counts = ValueNotifier<BellCounts>(c);
  addTearDown(counts.dispose);
  await t.pumpWidget(NotificationsScope(
    news: FakeNotificationsRepository(emptyNews()),
    counts: counts,
    child: MaterialApp(
      home: const Scaffold(body: Center(child: BellButton())),
      onGenerateRoute: (s) {
        final a = s.arguments;
        return MaterialPageRoute<void>(
          settings: s,
          builder: (_) => Scaffold(body: Text('route ${s.name} ${a is NotificationsRouteArgs ? a.chip : 'noargs'}')),
        );
      },
    ),
  ));
  await t.pump();
  return counts;
}

void main() {
  group('bell states', () {
    testWidgets('nothing: a plain bell, no badge', (t) async {
      await _pump(t, BellCounts.none);
      for (final s in [NotifShape.arrow, NotifShape.star, NotifShape.pill, NotifShape.diamond]) {
        expect(_shape(s), findsNothing, reason: '$s');
      }
    });

    testWidgets('update shows only the arrow; new notice only the star; both together', (t) async {
      final counts = await _pump(t, const BellCounts(update: true));
      expect(_shape(NotifShape.arrow), findsOneWidget);
      expect(_shape(NotifShape.star), findsNothing);
      counts.value = const BellCounts(newNotice: true);
      await t.pump();
      expect(_shape(NotifShape.arrow), findsNothing);
      expect(_shape(NotifShape.star), findsOneWidget);
      counts.value = const BellCounts(update: true, newNotice: true);
      await t.pump();
      expect(_shape(NotifShape.arrow), findsOneWidget);
      expect(_shape(NotifShape.star), findsOneWidget);
    });

    testWidgets('waiting gives the number pill, ready to parse the diamond with its number outside (auto-read only)',
        (t) async {
      final counts = await _pump(t, const BellCounts(waiting: 3, readyToParse: 2));
      if (kAutoReadCompiled) {
        expect(_shape(NotifShape.pill), findsOneWidget);
        expect(t.widget<NotifShapeIcon>(_shape(NotifShape.pill)).label, '3');
        expect(_shape(NotifShape.diamond), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const ValueKey('bell-diamond-number'))).data, '2');
        counts.value = const BellCounts(waiting: 150, readyToParse: 120);
        await t.pump();
        expect(t.widget<NotifShapeIcon>(_shape(NotifShape.pill)).label, '99+');
        expect(t.widget<Text>(find.byKey(const ValueKey('bell-diamond-number'))).data, '99+');
        counts.value = const BellCounts(waiting: 0, readyToParse: 4);
        await t.pump();
        expect(_shape(NotifShape.pill), findsNothing);
        expect(_shape(NotifShape.diamond), findsOneWidget);
      } else {
        expect(_shape(NotifShape.pill), findsNothing);
        expect(_shape(NotifShape.diamond), findsNothing);
      }
    });

    testWidgets('all four at once (auto-read) or the two shared ones (standard)', (t) async {
      await _pump(t, const BellCounts(update: true, newNotice: true, waiting: 5, readyToParse: 1));
      expect(_shape(NotifShape.arrow), findsOneWidget);
      expect(_shape(NotifShape.star), findsOneWidget);
      expect(_shape(NotifShape.pill), kAutoReadCompiled ? findsOneWidget : findsNothing);
      expect(_shape(NotifShape.diamond), kAutoReadCompiled ? findsOneWidget : findsNothing);
    });
  });

  group('spoken label', () {
    test('starts with Notifications for every combination', () {
      for (final u in [false, true]) {
        for (final n in [false, true]) {
          for (final w in [0, 3]) {
            for (final r in [0, 2]) {
              expect(
                bellLabelFor(BellCounts(update: u, newNotice: n, waiting: w, readyToParse: r)),
                startsWith('Notifications'),
              );
            }
          }
        }
      }
    });

    test('exact text', () {
      expect(bellLabelFor(BellCounts.none), 'Notifications');
      expect(bellLabelFor(const BellCounts(update: true, newNotice: true)),
          'Notifications, 1 update available, 1 new notice');
      if (kAutoReadCompiled) {
        expect(
          bellLabelFor(const BellCounts(update: true, newNotice: true, waiting: 3, readyToParse: 2)),
          'Notifications, 1 update available, 3 messages waiting for a category, 2 messages ready to parse, 1 new notice',
        );
      }
    });

    testWidgets('the screen reader reads one node with that label', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, const BellCounts(update: true));
      expect(find.bySemanticsLabel('Notifications, 1 update available'), findsOneWidget);
      h.dispose();
    });
  });

  testWidgets('tap opens the Notifications page with no chip argument (the page defaults to All)', (t) async {
    await _pump(t, const BellCounts(update: true, waiting: 2, readyToParse: 1));
    await t.tap(find.byKey(const ValueKey('bell-button')));
    await t.pumpAndSettle();
    expect(find.text('route ${Routes.notifications} noargs'), findsOneWidget);
  });

  group('BellCountsTracker', () {
    test('news flags are unread-only; waiting numbers pass through', () async {
      final news = StreamController<List<NewsItem>>();
      final waiting = StreamController<WaitingBellNumbers>();
      final tr = BellCountsTracker(news: news.stream, waiting: waiting.stream);
      addTearDown(() {
        tr.dispose();
        news.close();
        waiting.close();
      });
      news.add(typicalNews());
      waiting.add(const WaitingBellNumbers(4, 2));
      await Future<void>.delayed(Duration.zero);
      expect(tr.value.value, const BellCounts(update: true, newNotice: true, waiting: 4, readyToParse: 2));
      news.add([for (final i in typicalNews()) i.copyWith(readAt: DateTime(2026, 10, 18))]);
      await Future<void>.delayed(Duration.zero);
      expect(tr.value.value, const BellCounts(waiting: 4, readyToParse: 2));
    });
  });

  group('UpdatesNewsRepository (the inbox adapter)', () {
    test('maps notices, marks one read in memory, removes, no whats-new rows', () async {
      SharedPreferences.setMockInitialValues({});
      final inbox = UpdatesInbox(installedVersion: () => '0.1.0');
      await inbox.add(Notice(tag: 'v0.2.0', notes: 'n', receivedAt: DateTime(2026, 10, 1)));
      await inbox.add(Notice(tag: Notice.welcomeTag, notes: '', receivedAt: DateTime(2026, 10, 2), welcome: true));
      final repo = UpdatesNewsRepository(inbox);
      addTearDown(repo.dispose);
      final first = await repo.watchNews().first;
      expect(first.map((i) => i.kind).toSet(), {NewsKind.update, NewsKind.notice});
      expect(first.every((i) => i.isUnread), isTrue);

      final seen = <List<NewsItem>>[];
      final sub = repo.watchNews().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await repo.markRead('v0.2.0', DateTime(2026, 10, 3));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.where((i) => i.isUnread).map((i) => i.id), [Notice.welcomeTag]);
      await repo.remove(Notice.welcomeTag);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.map((i) => i.id), ['v0.2.0']);
      await sub.cancel();
    });
  });
}
