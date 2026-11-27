// Item 3 slice F-prep: Settings search index, matcher, overlay and button. Invented queries only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/settings/settings_search_autoread_rows.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_button.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_entry.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_index.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_matcher.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_overlay.dart';
import 'package:mmogo/ui/shell/secondary_scaffold.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

List<String> _titles(String q, {bool auto = true}) => [
  for (final e in matchSettingsSearch(q, SettingsSearchIndex.entries(autoRead: auto))) e.title,
];

Future<void> _pump(
  WidgetTester t, {
  double scale = 1,
  bool dark = false,
  bool auto = true,
  void Function(SettingsSearchEntry)? onPick,
}) async {
  t.view.physicalSize = const Size(360, 780);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
      child: MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (ctx) => SecondaryScaffold(
            title: 'Settings',
            followPalette: true,
            actions: [
              SettingsSearchButton(
                onPressed: () => showSettingsSearch(ctx, autoRead: auto, onPick: onPick ?? (_) {}),
              ),
            ],
            body: const Center(child: Text('page behind')),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.byKey(const Key('settingsSearchButton')));
  await t.pumpAndSettle();
}

void main() {
  // The Auto-read rows come from the auto-read wiring; these tests stand in for it.
  setUp(installSettingsSearchRows);
  tearDown(uninstallSettingsSearchRows);
  group('index', () {
    for (final auto in [true, false]) {
      test('no empty title, no duplicate id (autoRead=$auto)', () {
        final list = SettingsSearchIndex.entries(autoRead: auto);
        expect(list, isNotEmpty);
        final ids = <String>{};
        for (final e in list) {
          expect(e.title.trim(), isNotEmpty, reason: 'entry ${e.id} has an empty title');
          expect(e.sectionName.trim(), isNotEmpty, reason: 'entry ${e.id} has no section');
          expect(ids.add(e.id), isTrue, reason: 'duplicate id ${e.id}');
        }
      });
    }

    test('standard build drops Auto-read rows; Auto-read build keeps them in the agreed order', () {
      final std = SettingsSearchIndex.entries(autoRead: false);
      expect(std.any((e) => e.requiresAutoRead), isFalse);
      expect(std.map((e) => e.sectionName).toSet(), {'Look', 'Adding entries', 'Your data', 'About'});
      final full = SettingsSearchIndex.entries(autoRead: true);
      expect(full.where((e) => e.sectionName == 'Look'), hasLength(7));
      final sections = <String>[];
      for (final e in full) {
        if (sections.isEmpty || sections.last != e.sectionName) sections.add(e.sectionName);
      }
      expect(sections, ['Look', 'Adding entries', 'Reading messages', 'Auto-record', 'Your data', 'About']);
    });

    // "Every row on the Settings screen has an entry" is tested against the real page in settings_order_search_test.dart.

    test('chips are dropped when their target is missing', () {
      expect(SettingsSearchIndex.chips(autoRead: true), kSettingsSearchChips);
      final std = SettingsSearchIndex.chips(autoRead: false);
      expect(std, isNot(contains('Alerts')));
      expect(std, contains('Backup'));
    });
  });

  group('matcher', () {
    test('plain words find rows', () {
      expect(_titles('dark'), contains('Appearance'));
      for (final q in ['black', 'pure black', 'oled']) {
        expect(_titles(q), contains('Appearance'), reason: q);
      }
      expect(_titles('pause'), contains('Pause all Auto-record'));
      expect(_titles('csv'), contains('Export CSV'));
    });
    test('title starts-with beats contains beats keyword', () {
      final t = _titles('delete');
      expect(t.first, 'Delete held messages');
      expect(t.indexOf('Delete data'), lessThan(t.indexOf('Recently deleted')));
      expect(_titles('recently').first, 'Recently deleted');
      expect(_titles('time'), contains('Offer after N in a row')); // keyword only
      final q = matchSettingsSearch('chart', SettingsSearchIndex.entries(autoRead: true));
      expect(q.first.title, 'Month chart'); // starts-with; "Show withdrawals in the chart" contains
      expect(q[1].title, 'Show withdrawals in the chart');
    });
    test('case, spaces, accents and punctuation are ignored; empty finds nothing', () {
      expect(_titles('  EXPORT  csv '), contains('Export CSV'));
      expect(_titles('Expórt-CSV!'), contains('Export CSV'));
      expect(_titles('auto record'), contains('Pause all Auto-record'));
      expect(_titles(''), isEmpty);
      expect(_titles('  ?! '), isEmpty);
      expect(_titles('zzzz'), isEmpty);
    });
  });

  group('overlay', () {
    testWidgets('opens, shows chips, hides them while typing, lists results and picks', (t) async {
      SettingsSearchEntry? picked;
      await _pump(t, onPick: (e) => picked = e);
      await _open(t);
      expect(find.byKey(const Key('settingsSearchField')), findsOneWidget);
      expect(find.byKey(const Key('settingsSearchChip:Backup')), findsOneWidget);
      await t.enterText(find.byKey(const Key('settingsSearchField')), 'csv');
      await t.pump();
      expect(find.byKey(const Key('settingsSearchChip:Backup')), findsNothing);
      expect(find.byKey(const Key('settingsSearchResult:data.csv')), findsOneWidget);
      expect(find.text('Your data'), findsOneWidget);
      await t.tap(find.byKey(const Key('settingsSearchResult:data.csv')));
      await t.pumpAndSettle();
      expect(picked?.id, 'data.csv');
      expect(find.byKey(const Key('settingsSearchField')), findsNothing);
    });

    testWidgets('a chip fills the field; nothing found shows the message and the chips again', (t) async {
      await _pump(t);
      await _open(t);
      await t.tap(find.byKey(const Key('settingsSearchChip:Export')));
      await t.pump();
      expect(find.byKey(const Key('settingsSearchResult:data.csv')), findsOneWidget);
      await t.enterText(find.byKey(const Key('settingsSearchField')), 'zzzz');
      await t.pump();
      expect(find.text('Nothing found. Try Backup or Alerts.'), findsOneWidget);
      expect(find.byKey(const Key('settingsSearchChip:Backup')), findsOneWidget);
    });

    testWidgets('back arrow and a tap on the blur close it', (t) async {
      await _pump(t);
      await _open(t);
      await t.tap(find.byKey(const Key('settingsSearchBack')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsSearchField')), findsNothing);
      await _open(t);
      await t.tapAt(const Offset(180, 740));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsSearchField')), findsNothing);
    });

    testWidgets('plain scrim when animations are off (no BackdropFilter)', (t) async {
      await _pump(t);
      await _open(t);
      expect(find.byType(BackdropFilter), findsOneWidget);
      kSettingsSearchPlainScrim = true;
      addTearDown(() => kSettingsSearchPlainScrim = false);
      await t.tap(find.byKey(const Key('settingsSearchBack')));
      await t.pumpAndSettle();
      await _open(t);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('200% text, ${dark ? 'dark' : 'light'}: no overflow, 44 px targets, spoken names', (t) async {
        final h = t.ensureSemantics();
        await _pump(t, scale: 2, dark: dark);
        expect(t.getSize(find.byKey(const Key('settingsSearchButton'))).height, greaterThanOrEqualTo(44));
        expect(find.bySemanticsLabel('Search settings'), findsOneWidget);
        await _open(t);
        for (final c in SettingsSearchIndex.chips(autoRead: true)) {
          expect(t.getSize(find.byKey(Key('settingsSearchChip:$c'))).height, greaterThanOrEqualTo(44));
        }
        expect(t.getSize(find.byKey(const Key('settingsSearchBack'))).height, greaterThanOrEqualTo(44));
        await t.enterText(find.byKey(const Key('settingsSearchField')), 'a');
        await t.pump();
        final row = find.byKey(const Key('settingsSearchResult:look.appearance'));
        expect(t.getSize(row).height, greaterThanOrEqualTo(44));
        expect(find.bySemanticsLabel('Appearance, Look'), findsOneWidget);
        expect(t.takeException(), isNull);
        h.dispose();
      });
    }
  });
}
