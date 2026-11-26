// 0.2.2 item 2 U-RECENT-TAG (F-5, R4.17b): in "Recently recorded" the signed "Auto-record" tag
// (kHardAutoRecordTag) shows only on person rows written with no tap (recordedAutomatically = true).
// Yes and Parse rows (flag false) and airtime rows (flag true, own look) get no tag. The tag is
// visible text and part of the spoken label, holds at 200% text, light and dark. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_recorded_row.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications/recorded_auto_section.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

final _t0 = DateTime(2026, 11, 26, 9, 30);

Widget _host(Widget child, {String mode = 'light', double scale = 1.0, double width = 360}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child))),
        ),
      ),
    );

AutoRecorded _noTap({int id = 1, bool undone = false}) => AutoRecorded(
    rowId: id,
    amountCents: 45000,
    at: _t0,
    partyLabel: 'ALICE INVENTED',
    categoryName: 'Family/Friends',
    recordedAutomatically: true,
    inRecentlyDeleted: undone);

AutoRecorded _yes({int id = 2}) =>
    AutoRecorded(rowId: id, amountCents: 120000, at: _t0, partyLabel: 'BOB INVENTED', categoryName: 'Transport');

AutoRecorded _airtime({int id = 3}) => AutoRecorded(rowId: id, amountCents: 500, at: _t0, recordedAutomatically: true);

Widget _section(List<AutoRecorded> entries) =>
    RecordedAutoSection(entries: entries, now: _t0, onUndo: (_) {}, onChangeInSettings: () {});

Finder _rowOf(int id) => find.byKey(Key('auto-recorded-$id'));

Finder _tagIn(int id) => find.descendant(of: _rowOf(id), matching: find.text(kHardAutoRecordTag));

void main() {
  test('the tag is the signed level word', () => expect(kHardAutoRecordTag, 'Auto-record'));

  testWidgets('the tag shows on the no-tap person row only, not on Yes/Parse or airtime rows', (t) async {
    await t.pumpWidget(_host(_section([_noTap(), _yes(), _airtime()])));
    expect(find.text(kHardAutoRecordTag), findsOneWidget);
    expect(_tagIn(1), findsOneWidget);
    expect(_tagIn(2), findsNothing);
    expect(_tagIn(3), findsNothing);
  });

  testWidgets('a Yes or Parse row (flag 0) has no tag on its own', (t) async {
    await t.pumpWidget(_host(AutoRecordedRow(entry: _yes(), now: _t0, onUndo: () {})));
    expect(find.text(kHardAutoRecordTag), findsNothing);
    expect(find.bySemanticsLabel(RegExp(kHardAutoRecordTag)), findsNothing);
  });

  testWidgets('airtime rows flagged 1 keep their own look: no tag, title, line, link, icon', (t) async {
    await t.pumpWidget(
        _host(AutoRecordedRow(entry: _airtime(), now: _t0, onUndo: () {}, onChangeInSettings: () {})));
    expect(find.text(kHardAutoRecordTag), findsNothing);
    expect(find.byKey(const Key('notifRowChip')), findsNothing);
    expect(find.text('Airtime for myself, Ksh 5'), findsOneWidget);
    expect(find.text(kAutoRecordedSub), findsOneWidget);
    expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(kHardAutoRecordTag)), findsNothing);
  });

  testWidgets('the tag is text, and the row is read out starting with it (not colour only)', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(AutoRecordedRow(entry: _noTap(), now: _t0, onUndo: () {})));
    final tag = t.widget<Text>(_tagIn(1));
    expect(tag.data, kHardAutoRecordTag);
    expect(find.bySemanticsLabel(RegExp('^$kHardAutoRecordTag\\. ALICE INVENTED, Ksh 450\\.')), findsOneWidget);
    // Undo still names the row by its title only.
    expect(find.bySemanticsLabel('$kAutoRecordedUndo: ALICE INVENTED, Ksh 450'), findsOneWidget);
    h.dispose();
  });

  testWidgets('an undone no-tap row keeps its tag (it says how the row was written)', (t) async {
    await t.pumpWidget(_host(AutoRecordedRow(entry: _noTap(undone: true), now: _t0, onUndo: () {})));
    expect(_tagIn(1), findsOneWidget);
    expect(find.text(kAutoRecordedUndone), findsOneWidget);
  });

  for (final mode in ['light', 'dark']) {
    for (final w in [320.0, 360.0]) {
      testWidgets('200% text, $w wide, $mode: tagged and plain person rows lay out with no overflow', (t) async {
        await t.pumpWidget(_host(_section([_noTap(), _yes()]), mode: mode, scale: 2.0, width: w));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(_tagIn(1), findsOneWidget);
        final tagBox = t.getRect(_tagIn(1));
        final rowBox = t.getRect(_rowOf(1));
        expect(tagBox.right, lessThanOrEqualTo(rowBox.right));
        expect(tagBox.left, greaterThanOrEqualTo(rowBox.left));
        final undo = find.ancestor(of: find.text(kAutoRecordedUndo).first, matching: find.byType(InkWell)).first;
        expect(t.getSize(undo).height, greaterThanOrEqualTo(44));
        expect(t.getSize(undo).width, greaterThanOrEqualTo(44));
      });
    }
  }

  testWidgets('right-to-left: the tagged row lays out with no overflow', (t) async {
    await t.pumpWidget(_host(Directionality(textDirection: TextDirection.rtl, child: _section([_noTap(), _yes()]))));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(_tagIn(1), findsOneWidget);
  });
}
