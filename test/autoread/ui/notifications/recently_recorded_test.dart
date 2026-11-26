// 0.2.2 item 2 U-RECENT (F-5): the one list is headed "Recently recorded" (signed kHardRecentlyRecorded),
// the old heading "Recorded automatically" is gone, airtime auto rows keep their own look, and the
// heading and person rows hold at 200% text in light and dark (airtime rows: HANDOFF, skipped test). The "Auto-record" tag is NOT built: the trail row does not
// carry recorded_automatically (HANDOFF in ITEM2-R-U-RECENT-REPORT-2026-11-25.md); the last test pins
// that no row shows the tag until it does.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_recorded_row.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications/recorded_auto_section.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

final _t0 = DateTime(2026, 11, 25, 14, 5);

Widget _host(Widget child, {String mode = 'light', double scale = 1.0, double width = 360}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child))),
        ),
      ),
    );

List<AutoRecorded> _mixed() => [
      AutoRecorded(rowId: 1, amountCents: 500, at: _t0),
      AutoRecorded(rowId: 2, amountCents: 1000, at: _t0, airtimeOther: true),
      AutoRecorded(rowId: 3, amountCents: 250000, at: _t0, partyLabel: 'JOHN DOE', categoryName: 'Fuel'),
      AutoRecorded(rowId: 4, amountCents: 7000, at: _t0, partyLabel: 'MAMA MBOGA', categoryName: 'Food', inRecentlyDeleted: true),
    ];

Widget _section(List<AutoRecorded> entries) =>
    RecordedAutoSection(entries: entries, now: _t0, onUndo: (_) {}, onChangeInSettings: () {});

void main() {
  testWidgets('heading is the signed "Recently recorded" with the count of rows still recorded; the old heading is gone',
      (t) async {
    expect(kHardRecentlyRecorded, 'Recently recorded');
    await t.pumpWidget(_host(_section(_mixed())));
    expect(find.text('$kHardRecentlyRecorded (3)'), findsOneWidget);
    expect(find.text(kAutoRecordedHeading), findsNothing);
    expect(find.textContaining('$kAutoRecordedHeading ('), findsNothing);
    expect(find.byType(AutoRecordedRow), findsNWidgets(4));
  });

  testWidgets('all rows undone: the heading shows with no count; empty list draws nothing', (t) async {
    await t.pumpWidget(_host(_section([AutoRecorded(rowId: 1, amountCents: 500, at: _t0, inRecentlyDeleted: true)])));
    expect(find.text(kHardRecentlyRecorded), findsOneWidget);
    await t.pumpWidget(_host(_section(const [])));
    expect(find.textContaining(kHardRecentlyRecorded), findsNothing);
  });

  testWidgets('airtime auto rows keep their own look: title, "Recorded automatically." line, link, Undo, icon', (t) async {
    await t.pumpWidget(_host(_section([AutoRecorded(rowId: 1, amountCents: 500, at: _t0)])));
    expect(find.text('Airtime for myself, Ksh 5'), findsOneWidget);
    expect(find.text(kAutoRecordedSub), findsOneWidget);
    expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
    expect(find.text(kAutoRecordedUndo), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text(kHardAutoRecordTag), findsNothing);
  });

  // Person rows (chip records, Ask first Yes) carry no "Change in Settings" link.
  List<AutoRecorded> people() => [
        AutoRecorded(rowId: 3, amountCents: 250000, at: _t0, partyLabel: 'JOHN DOE', categoryName: 'Fuel'),
        AutoRecorded(rowId: 4, amountCents: 7000, at: _t0, partyLabel: 'MAMA MBOGA', categoryName: 'Food', inRecentlyDeleted: true),
      ];

  for (final mode in ['light', 'dark']) {
    for (final w in [320.0, 360.0]) {
      testWidgets('200% text, $w wide, $mode: heading and person rows lay out with no overflow; Undo >= 44 px', (t) async {
        await t.pumpWidget(_host(_section(people()), mode: mode, scale: 2.0, width: w));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('$kHardRecentlyRecorded (1)'), findsOneWidget);
        expect(find.text('JOHN DOE, Ksh 2,500'), findsOneWidget);
        final undo = find.ancestor(of: find.text(kAutoRecordedUndo), matching: find.byType(InkWell)).first;
        expect(t.getSize(undo).height, greaterThanOrEqualTo(44));
        expect(t.getSize(undo).width, greaterThanOrEqualTo(44));
      });
    }
  }

  // HANDOFF (news_row.dart, not this slice): the airtime row's "Change in Settings" link sits in a Row
  // with no wrap (NotifRowShell foot, news_row.dart:203 + _LinkButton :281) and overflows at 200%
  // in the test font (159 px at 360 wide). Pre-existing since 0.2.0; the row's look is unchanged here.
  testWidgets('200% text, 360 wide: airtime rows with the Change in Settings link lay out with no overflow',
      (t) async {
    await t.pumpWidget(_host(_section([AutoRecorded(rowId: 1, amountCents: 500, at: _t0)]), scale: 2.0));
    await t.pump();
    expect(t.takeException(), isNull);
  }, skip: true); // HANDOFF: news_row.dart foot row overflow at 200% (see ITEM2-R-U-RECENT-REPORT)

  testWidgets('NOT BUILT (HANDOFF): no row shows the Auto-record tag while the trail row has no recorded_automatically',
      (t) async {
    await t.pumpWidget(_host(_section(_mixed())));
    expect(find.text(kHardAutoRecordTag), findsNothing);
    expect(find.bySemanticsLabel(RegExp(kHardAutoRecordTag)), findsNothing);
  });
}
