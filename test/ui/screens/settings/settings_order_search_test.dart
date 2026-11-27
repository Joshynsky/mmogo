// Item 3 slice E: the Settings order (both builds), the search wired to the page (jump and pulse), 200% text.
// Standard run: Look > Adding entries > Your data > About. Auto-read run (--dart-define=MMOGO_AUTOREAD=true):
// Look > Adding entries > Reading messages > Auto-record > Your data > About.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/ui/settings/settings_search_autoread_rows.dart';
import 'package:mmogo/ui/screens/settings/search/settings_search_index.dart';
import 'package:mmogo/ui/widgets/coach_tour.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';

import '../../../support/settings_harness.dart';

double _y(WidgetTester t, Finder f) => t.getTopLeft(f.first).dy;

Finder _outlineAround(String text) => find.descendant(
      of: find.ancestor(of: find.text(text), matching: find.byType(HighlightPulse)),
      matching: find.byKey(const Key('highlightOutline')),
    );

Future<void> _search(WidgetTester t, String query, String resultId) async {
  await t.tap(find.byKey(const Key('settingsSearchButton')));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('settingsSearchField')), query);
  await t.pump();
  await t.tap(find.byKey(Key('settingsSearchResult:$resultId')));
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _endPulse(WidgetTester t) => t.pump(kHighlightDuration + const Duration(seconds: 1));

void main() {
  setUp(() {
    settingsHarnessSetUp();
    if (kAutoReadCompiled) installSettingsSearchRows(); // the auto-read wiring does this at start
  });
  tearDown(() {
    uninstallSettingsSearchRows();
    settingsHarnessTearDown();
  });

  group('order', () {
    testWidgets('section order for this build', (t) async {
      await pumpSettings(t, size: const Size(400, 6000));
      final labels = ['LOOK', 'ADDING ENTRIES', if (kAutoReadCompiled) ...['READING MESSAGES', 'AUTO-RECORD'], 'YOUR DATA', 'ABOUT'];
      for (final l in labels) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      for (var i = 1; i < labels.length; i++) {
        expect(_y(t, find.text(labels[i - 1])) < _y(t, find.text(labels[i])), isTrue, reason: '${labels[i - 1]} before ${labels[i]}');
      }
      if (!kAutoReadCompiled) {
        expect(find.text('READING MESSAGES'), findsNothing);
        expect(find.text('AUTO-RECORD'), findsNothing);
        // The standard build keeps the Remembered recipients row in Adding entries, and nothing about People.
        expect(find.text('Remembered recipients'), findsOneWidget);
        expect(find.text('People'), findsNothing);
        expect(_y(t, find.text('Remembered recipients')) < _y(t, find.text('YOUR DATA')), isTrue);
      }
    });

    testWidgets('auto-read: rows inside Reading messages and Auto-record', (t) async {
      if (!kAutoReadCompiled) return;
      await pumpSettings(t, size: const Size(400, 6000));
      final reading = ['Read M-Pesa messages', 'Parse from the notification', 'What alerts show', 'Trouble turning it on?', 'Delete held messages'];
      for (var i = 1; i < reading.length; i++) {
        expect(_y(t, find.text(reading[i - 1])) < _y(t, find.text(reading[i])), isTrue, reason: reading[i]);
      }
      expect(_y(t, find.text('ADDING ENTRIES')) < _y(t, find.text(reading.first)), isTrue);
      expect(_y(t, find.text(reading.last)) < _y(t, find.text('AUTO-RECORD')), isTrue);
      final auto = ['People', 'Pause all Auto-record', 'Offer Ask first', 'Offer after N in a row'];
      for (final a in auto) {
        expect(find.text(a), findsOneWidget, reason: a);
      }
      for (var i = 1; i < auto.length; i++) {
        expect(_y(t, find.text(auto[i - 1])) < _y(t, find.text(auto[i])), isTrue, reason: auto[i]);
      }
      expect(_y(t, find.text('AUTO-RECORD')) < _y(t, find.text('People')), isTrue);
      expect(_y(t, find.text(auto.last)) < _y(t, find.text('YOUR DATA')), isTrue);
      // People shows the count and the airtime state; the Remembered row is gone from Adding entries.
      expect(find.textContaining('3 people'), findsOneWidget);
      expect(find.text('Remembered recipients'), findsNothing);
      expect(find.text('Remembered, suggestions and auto-record'), findsNothing);
      // Nothing is shown twice.
      for (final s in [...reading, ...auto]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('SUGGESTIONS'), findsNothing);
    });

    testWidgets('every row on the page has a search entry, and every entry has a row (or a row it lands on)', (t) async {
      await pumpSettings(t, size: const Size(400, 6000));
      final entries = SettingsSearchIndex.entries().map((e) => e.id).toSet();
      final shown = settingsRowIdsFromScreen(t);
      expect(shown.difference(entries), isEmpty, reason: 'rows without a search entry');
      expect(entries.difference(settingsRowIdsFromScreen(t, withAliases: true)), isEmpty, reason: 'entries that land on no row');
      expect(shown.where((id) => id.startsWith('look.')), hasLength(7));
    });
  });

  group('search jump', () {
    testWidgets('a result scrolls to the row and pulses it (short screen)', (t) async {
      await pumpSettings(t, size: const Size(400, 520));
      expect(find.byKey(const Key('settingsSearchButton')), findsOneWidget);
      await _search(t, 'feedback', 'about.feedback');
      expect(find.byKey(const Key('settingsSearchField')), findsNothing);
      expect(_outlineAround('Send feedback'), findsOneWidget);
      final dy = t.getTopLeft(find.text('Send feedback')).dy;
      expect(dy, inInclusiveRange(0, 520));
      await _endPulse(t);
    });

    testWidgets('picking the same row again pulses again; a row near the top pulses too', (t) async {
      await pumpSettings(t, size: const Size(400, 520));
      await _search(t, 'csv', 'data.csv');
      expect(_outlineAround('Export CSV'), findsOneWidget);
      await _endPulse(t);
      await _search(t, 'csv', 'data.csv');
      expect(_outlineAround('Export CSV'), findsOneWidget);
      await _endPulse(t);
      await _search(t, 'dark', 'look.appearance');
      expect(_outlineAround('Appearance'), findsOneWidget);
      expect(t.getTopLeft(find.text('Appearance')).dy, inInclusiveRange(0, 520));
      await _endPulse(t);
    });

    testWidgets('the page works as before after a pick (a switch still flips)', (t) async {
      await pumpSettings(t, size: const Size(400, 800));
      await _search(t, 'receiver', 'adding.receiver');
      await _endPulse(t);
      final sw = find.descendant(of: find.byKey(const Key('settingsCaptureReceiver')), matching: find.byType(Switch));
      expect(t.widget<Switch>(sw).value, isTrue);
      await t.tap(sw);
      await t.pump();
      expect(t.widget<Switch>(sw).value, isFalse);
    });

    testWidgets('auto-read: Pause, Hide details (generic alerts lands on What alerts show) and Airtime (lands on People)', (t) async {
      if (!kAutoReadCompiled) return;
      await pumpSettings(t, size: const Size(400, 520));
      await _search(t, 'pause', 'auto.pause');
      expect(_outlineAround('Pause all Auto-record'), findsOneWidget);
      await _endPulse(t);
      await _search(t, 'hide', 'reading.hide');
      expect(find.text('Hide details after'), findsNothing);
      expect(_outlineAround('What alerts show'), findsOneWidget);
      await _endPulse(t);
      await _search(t, 'airtime', 'auto.airtime');
      expect(_outlineAround('People'), findsOneWidget);
      await _endPulse(t);
    });

    testWidgets('standard build: search offers only the rows it has', (t) async {
      if (kAutoReadCompiled) return;
      await pumpSettings(t, size: const Size(400, 800));
      await t.tap(find.byKey(const Key('settingsSearchButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsSearchChip:Backup')), findsOneWidget);
      expect(find.byKey(const Key('settingsSearchChip:Alerts')), findsNothing);
      await t.enterText(find.byKey(const Key('settingsSearchField')), 'airtime');
      await t.pump();
      expect(find.text('Nothing found. Try Backup or Alerts.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('settingsSearchField')), 'pause');
      await t.pump();
      expect(find.byKey(const Key('settingsSearchResult:auto.pause')), findsNothing);
      await t.enterText(find.byKey(const Key('settingsSearchField')), 'remembered');
      await t.pump();
      expect(find.byKey(const Key('settingsSearchResult:adding.remembered')), findsOneWidget);
    });
  });

  group('coach tour', () {
    setUp(() => CoachTour.autoStartDisabled = false);
    tearDown(() => CoachTour.autoStartDisabled = true);

    testWidgets('auto-read: 4 steps, the Auto-record step sits before Your data; standard: 3 steps', (t) async {
      await pumpSettings(t, size: const Size(400, 2600));
      final steps = kAutoReadCompiled ? 4 : 3;
      expect(find.text('1 of $steps'), findsOneWidget);
      await t.tap(find.byKey(coachTourNextKey));
      await t.pumpAndSettle();
      expect(find.text('2 of $steps'), findsOneWidget);
      expect(find.textContaining(kAutoReadCompiled ? 'repeat receivers, or manage' : 'review the names mmogo remembers'), findsOneWidget);
      await t.tap(find.byKey(coachTourNextKey));
      await t.pumpAndSettle();
      if (kAutoReadCompiled) {
        expect(find.text('3 of 4'), findsOneWidget);
        expect(find.textContaining('Choose who mmogo records for you'), findsOneWidget);
        await t.tap(find.byKey(coachTourNextKey));
        await t.pumpAndSettle();
      }
      expect(find.text('$steps of $steps'), findsOneWidget);
      expect(find.textContaining('CSV'), findsWidgets);
      await t.tap(find.byKey(coachTourNextKey)); // Done
      await t.pumpAndSettle();
      expect(find.byKey(coachTourBubbleKey), findsNothing);
    });
  });

  for (final dark in [false, true]) {
    testWidgets('200% text, ${dark ? 'dark' : 'light'}: no overflow, search icon 44 px, a jump still lands', (t) async {
      final h = t.ensureSemantics();
      await pumpSettings(t, size: const Size(400, 800), scale: 2, appearance: dark ? 'dark' : 'light');
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const Key('settingsSearchButton'))).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Search settings'), findsOneWidget);
      await _search(t, 'feedback', 'about.feedback');
      expect(t.takeException(), isNull);
      expect(_outlineAround('Send feedback'), findsOneWidget);
      expect(t.getTopLeft(find.text('Send feedback')).dy, inInclusiveRange(0, 800));
      await _endPulse(t);
      h.dispose();
    });
  }
}
