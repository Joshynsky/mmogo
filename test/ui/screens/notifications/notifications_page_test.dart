// F3: the Notifications page, shared. Runs in both flavors: the News tests
// open on the News chip (the only chip in the standard flavor); tests that
// only make sense without auto-read are skipped in the autoread flavor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/news_heading_bar.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../../support/news_fakes.dart';
import '../../../support/waiting_fakes.dart';

Widget _host(Widget page, {double scale = 1.0}) => MaterialApp(
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: page,
    );

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 800);
  addTearDown(t.view.reset);
}

Future<FakeNotificationsRepository> _open(
  WidgetTester t,
  List<NewsItem> items, {
  double width = 360,
  double scale = 1.0,
  NotifChip chip = NotifChip.news,
  bool withWaiting = false,
  VoidCallback? onBack,
}) async {
  _size(t, width);
  final repo = FakeNotificationsRepository(items);
  await t.pumpWidget(_host(
    NotificationsPage(
      news: repo,
      waiting: withWaiting
          ? FakeAutoReadWaitingRepository.forSet(WaitingDataSet.typical, () => kFakeNow)
          : null,
      initialChip: chip,
      clock: () => kFakeNow,
      onBack: onBack,
    ),
    scale: scale,
  ));
  await t.pump();
  await t.pump();
  return repo;
}

NewsItem _n(String id, int ageMin, {int? readAgeDays, NewsKind kind = NewsKind.notice}) => NewsItem(
      id: id,
      kind: kind,
      title: 'Title $id',
      createdAt: kFakeNow.subtract(Duration(minutes: ageMin)),
      readAt: readAgeDays == null ? null : kFakeNow.subtract(Duration(days: readAgeDays)),
    );

double _top(WidgetTester t, String id) => t.getTopLeft(find.byKey(Key('news-row-$id'))).dy;

Finder _switchOpt(String label) => find.descendant(
    of: find.byType(NewsHeadingBar), matching: find.text(label));

Finder _row(String id) => find.byKey(Key('news-row-$id'));

String _heading(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .firstWhere((s) => s.startsWith('$kNewsHeading ('), orElse: () => '');

void main() {
  group('News on the page (both flavors)', () {
    testWidgets('title, back, and unread rows newest first with unread-only count', (t) async {
      var backs = 0;
      await _open(t, typicalNews(), onBack: () => backs++);
      expect(find.text(kNotificationsTitle), findsOneWidget);
      expect(find.bySemanticsLabel(kNotificationsBackLabel), findsOneWidget);
      await t.tap(find.byKey(const Key('notif-back')));
      expect(backs, 1);
      // Typical: 4 unread (n1, n2, update, what's new), 1 read.
      expect(_heading(t), 'News (4)');
      expect(_row('n3'), findsNothing); // read: not in Unread
      // Newest first: update (1 day), what's new (9 days) vs notices 2 and 4 days.
      expect(_top(t, 'upd1'), lessThan(_top(t, 'n1')));
      expect(_top(t, 'n1'), lessThan(_top(t, 'n2')));
      expect(_top(t, 'n2'), lessThan(_top(t, 'wn1')));
    });

    testWidgets('Read moves a notice to Read view, count falls, row dims', (t) async {
      await _open(t, typicalNews());
      await t.tap(find.bySemanticsLabel('$kNewsActionRead: Back up your data'));
      await t.pump();
      await t.pump();
      expect(_heading(t), 'News (3)');
      expect(_row('n1'), findsNothing);
      await t.tap(_switchOpt(kNewsSwitchRead));
      await t.pump();
      expect(find.byKey(const Key('news-row-n1')), findsOneWidget);
      expect(find.byKey(const Key('news-row-n3')), findsOneWidget);
      expect(find.byKey(const Key('notifRowDimIcon')), findsNWidgets(2)); // read rows dim
      expect(find.text(kNewsActionRemove), findsNWidgets(2));
      expect(_heading(t), 'News (3)'); // still the unread count in the Read view
    });

    testWidgets('Dismiss removes the row and shows the toast', (t) async {
      final repo = await _open(t, typicalNews());
      await t.tap(find.bySemanticsLabel('$kNewsActionDismiss: Back up your data'));
      await t.pump();
      await t.pump();
      expect(repo.items.any((i) => i.id == 'n1'), isFalse);
      expect(find.text(kNewsToastDismissed), findsOneWidget);
      expect(_heading(t), 'News (3)');
    });

    testWidgets('Update on the update row swaps it for an unread What\'s new row', (t) async {
      await _open(t, typicalNews());
      await t.tap(find.bySemanticsLabel('$kNewsActionUpdate: $kUpdateRowTitle'));
      await t.pump();
      await t.pump();
      expect(_row('upd1'), findsNothing);
      expect(_row('wn-upd1'), findsOneWidget);
      expect(_row('wn1'), findsOneWidget);
      expect(_heading(t), 'News (4)');
    });

    testWidgets('99+ cap on the News heading', (t) async {
      await _open(t, [for (var i = 0; i < 120; i++) _n('x$i', i + 1)]);
      expect(_heading(t), 'News (99+)');
    });

    testWidgets('empty states: unread and read', (t) async {
      await _open(t, emptyNews());
      expect(find.text(kNewsEmptyUnreadTitle), findsOneWidget);
      expect(find.text(kNewsEmptyUnreadBody), findsOneWidget);
      await t.tap(_switchOpt(kNewsSwitchRead));
      await t.pump();
      expect(find.text(kNewsEmptyReadTitle), findsOneWidget);
      expect(find.text(kNewsEmptyReadBody), findsOneWidget);
    });

    testWidgets('30-day expiry: read 29 days ago stays in Read, 30 days ago does not', (t) async {
      await _open(t, [_n('keep', 100, readAgeDays: 29), _n('gone', 200, readAgeDays: 30)]);
      await t.tap(_switchOpt(kNewsSwitchRead));
      await t.pump();
      expect(find.byKey(const Key('news-row-keep')), findsOneWidget);
      expect(find.byKey(const Key('news-row-gone')), findsNothing);
    });

    for (final w in [360.0, 390.0]) {
      testWidgets('layout at ${w.toInt()} px, text 1.3: no overflow, 44 px targets, labels', (t) async {
        await _open(t, typicalNews(), width: w, scale: 1.3);
        expect(t.takeException(), isNull);
        for (final f in [
          find.byKey(const Key('notif-back')),
          find.ancestor(of: _switchOpt(kNewsSwitchUnread), matching: find.byType(InkWell)),
          find.ancestor(of: _switchOpt(kNewsSwitchRead), matching: find.byType(InkWell)),
          find.ancestor(of: find.text(kNewsActionDismiss).first, matching: find.byType(InkWell)).first,
        ]) {
          final s = t.getSize(f);
          expect(s.height, greaterThanOrEqualTo(44), reason: '$f');
          expect(s.width, greaterThanOrEqualTo(44), reason: '$f');
        }
        expect(find.bySemanticsLabel(kNotificationsBackLabel), findsOneWidget);
        expect(find.bySemanticsLabel(kNewsSwitchLabel), findsOneWidget);
      });
    }
  });

  group('Standard flavor', () {
    final skip = kAutoReadCompiled ? 'standard flavor only' : null;

    testWidgets('no chip bar at all; News only', (t) async {
      await _open(t, typicalNews(), chip: NotifChip.all);
      for (final c in NotifChip.values) {
        expect(find.byKey(Key('notif-chip-${c.name}')), findsNothing, reason: c.name);
      }
      expect(find.text(kChipNews), findsNothing); // not even a chip; only the heading remains
      expect(_heading(t), 'News (4)');
    }, skip: skip != null);

    testWidgets('zero auto-read words anywhere in the tree, even with a waiting repo given', (t) async {
      await _open(t, typicalNews(), chip: NotifChip.parse, withWaiting: true);
      final texts = <String>[
        for (final w in t.widgetList<Text>(find.byType(Text))) w.textSpan?.toPlainText() ?? w.data ?? '',
        for (final s in t.widgetList<Semantics>(find.byType(Semantics)))
          if (s.properties.label != null) s.properties.label!,
      ].join(' | ').toLowerCase();
      expect(texts, isNotEmpty);
      for (final word in [
        'parse', 'categor', 'waiting', 'paste', 'm-pesa', 'unreadable', 'could not read',
        'ready', 'reading', 'held', 'expires',
      ]) {
        expect(texts.contains(word), isFalse, reason: 'found "$word" in: $texts');
      }
      for (final s in allAutoReadCopy()) {
        expect(texts.contains(s.toLowerCase()), isFalse, reason: s);
      }
      for (final s in kAutoReadPageCopyAll) {
        expect(texts.contains(s.toLowerCase()), isFalse, reason: s);
      }
    }, skip: skip != null);
  });

  test('the copy added for the page has no banned phrase', () {
    const banned = ['100% private', 'never', 'cannot read other messages', 'no permissions', 'within 24 hours'];
    for (final s in kNotificationsPageCopyAll) {
      for (final b in banned) {
        expect(s.toLowerCase().contains(b), isFalse, reason: s);
      }
    }
  });
}
