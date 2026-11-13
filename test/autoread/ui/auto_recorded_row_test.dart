// AutoRecordedRow: trail row text for both airtime kinds, Undo, the
// "Change in Settings" link, text scale 1.3 in light and dark, spoken label.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_recorded_row.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

final _t0 = DateTime(2026, 11, 3, 14, 5);

Widget _host(Widget child, {String mode = 'light', double scale = 1.0}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

AutoRecorded _entry({bool other = false}) =>
    AutoRecorded(rowId: 3, amountCents: 500, at: _t0, airtimeOther: other);

void main() {
  test('autoRecordedTitle reads both kinds', () {
    expect(autoRecordedTitle('Ksh 5'), 'Airtime for myself, Ksh 5');
    expect(autoRecordedTitle('Ksh 5', other: true), 'Airtime for another number, Ksh 5');
  });

  testWidgets('both kinds show the title and "Recorded automatically."', (t) async {
    await t.pumpWidget(_host(AutoRecordedRow(entry: _entry(), now: _t0, onUndo: () {})));
    expect(find.text('Airtime for myself, Ksh 5'), findsOneWidget);
    expect(find.text('Recorded automatically.'), findsOneWidget);
    await t.pumpWidget(_host(AutoRecordedRow(entry: _entry(other: true), now: _t0, onUndo: () {})));
    expect(find.text('Airtime for another number, Ksh 5'), findsOneWidget);
  });

  testWidgets('Undo still calls onUndo; the link calls onChangeInSettings', (t) async {
    var undos = 0, links = 0;
    await t.pumpWidget(_host(AutoRecordedRow(
        entry: _entry(), now: _t0, onUndo: () => undos++, onChangeInSettings: () => links++)));
    await t.tap(find.text('Undo'));
    expect(undos, 1);
    expect(links, 0);
    await t.tap(find.text('Change in Settings'));
    expect(links, 1);
    expect(undos, 1);
  });

  testWidgets('no link while the callback is null', (t) async {
    await t.pumpWidget(_host(AutoRecordedRow(entry: _entry(), now: _t0, onUndo: () {})));
    expect(find.text('Change in Settings'), findsNothing);
  });

  testWidgets('a row in Recently deleted says so, with no Undo', (t) async {
    final e = AutoRecorded(rowId: 3, amountCents: 500, at: _t0, inRecentlyDeleted: true);
    await t.pumpWidget(_host(AutoRecordedRow(entry: e, now: _t0, onUndo: () {})));
    expect(find.text(kAutoRecordedUndone), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('text scale 1.3, $mode: no overflow, link and Undo reachable', (t) async {
      await t.pumpWidget(_host(
          AutoRecordedRow(entry: _entry(other: true), now: _t0, onUndo: () {}, onChangeInSettings: () {}),
          mode: mode,
          scale: 1.3));
      expect(t.takeException(), isNull);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Change in Settings'), findsOneWidget);
    });
  }

  testWidgets('spoken label carries title and sub line, no heading (PM 13-11-2026)', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(AutoRecordedRow(entry: _entry(), now: _t0, onUndo: () {})));
    expect(
        find.bySemanticsLabel(RegExp(r'Airtime for myself, Ksh 5\. Recorded automatically\.')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Recorded automatically\. Airtime for myself')), findsNothing);
    h.dispose();
  });
}
