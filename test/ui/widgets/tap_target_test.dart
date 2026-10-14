// 0.1.2 S4b (TS1): every shared small control reaches 44 x 44 logical px at
// text scale 1.0, and a tap on the ring around the visible control works.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics/parts.dart';
import 'package:mmogo/ui/shell/chrome_widgets.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/period_pill.dart';
import 'package:mmogo/ui/widgets/removable_chip.dart';
import 'package:mmogo/ui/widgets/tap_target.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
);

/// Fails (throws TestFailure) when [finder]'s unscaled size is under 44 in
/// either direction. Used on the real widgets and, as the negative case, on a
/// 36 px box.
void _expectAtLeast44(WidgetTester t, Finder finder, String what) {
  expect(finder, findsOneWidget, reason: what);
  final s = t.getSize(finder);
  expect(s.width, greaterThanOrEqualTo(44), reason: '$what width ${s.width}');
  expect(s.height, greaterThanOrEqualTo(44), reason: '$what height ${s.height}');
}

void main() {
  final p = AppPalette.light;

  testWidgets('the checker can fail: a 36 px box is reported (negative case)', (t) async {
    await t.pumpWidget(_host(const SizedBox(key: Key('small'), width: 36, height: 36)));
    expect(() => _expectAtLeast44(t, find.byKey(const Key('small')), 'small'), throwsA(isA<TestFailure>()));
  });

  testWidgets('shared Back button (IconCircleButton, 36 px visible) is >= 44 and its ring taps', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _host(IconCircleButton(key: const Key('back'), icon: Icons.arrow_back, size: 36, onTap: () => taps++)),
    );
    _expectAtLeast44(t, find.byKey(const Key('back')), 'Back button');
    // The visible circle keeps its 36 px.
    expect(t.getSize(find.descendant(of: find.byKey(const Key('back')), matching: find.byType(Material)).first), const Size(36, 36));
    final box = t.getRect(find.byKey(const Key('back')));
    await t.tapAt(box.topLeft + const Offset(1, 1)); // the ring, outside the 36 px circle
    expect(taps, 1);
  });

  testWidgets('default IconCircleButton (32 px visible) is >= 44', (t) async {
    await t.pumpWidget(_host(IconCircleButton(key: const Key('ib'), icon: Icons.person, onTap: () {})));
    _expectAtLeast44(t, find.byKey(const Key('ib')), 'IconCircleButton');
  });

  testWidgets('AnalyticsRoundButton (pager prev/next, 28 px visible) is >= 44 and its ring taps', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _host(
        AnalyticsRoundButton(
          key: const Key('prev'),
          size: 28,
          icon: Icons.chevron_left,
          iconSize: 16,
          tooltip: 'Earlier',
          background: p.track,
          foreground: p.ink,
          onTap: () => taps++,
        ),
      ),
    );
    _expectAtLeast44(t, find.byKey(const Key('prev')), 'pager button');
    await t.tapAt(t.getRect(find.byKey(const Key('prev'))).topLeft + const Offset(1, 1));
    expect(taps, 1);
  });

  testWidgets('PeriodPill: both halves are >= 44 tall, the visible pill keeps its height, each half taps on its ring', (t) async {
    var gran = 0, val = 0;
    await t.pumpWidget(
      _host(
        PeriodPill(
          palette: p,
          granKey: GlobalKey(),
          valueKey: GlobalKey(),
          granularity: 'Week',
          value: '12–18 Oct',
          onGranularity: () => gran++,
          onValue: () => val++,
        ),
      ),
    );
    final halves = find.byType(TapTarget);
    expect(halves, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(t.getSize(halves.at(i)).height, greaterThanOrEqualTo(44), reason: 'half $i');
    }
    // Visible pill: the primary half is still the same ~26 px tall as before.
    expect(t.getSize(find.byKey(const Key('analyticsGranularity'))).height, lessThan(30));
    await t.tapAt(t.getRect(halves.at(0)).topLeft + const Offset(20, 1));
    await t.tapAt(t.getRect(halves.at(1)).topLeft + const Offset(20, 1));
    expect([gran, val], [1, 1]);
  });

  testWidgets('RemovableChip (filter chip) is >= 44 tall and its ring taps', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _host(
        RemovableChip(
          key: const Key('chip'),
          palette: p,
          label: 'Shopping',
          semanticsLabel: 'Shopping, tap to clear',
          onTap: () => taps++,
        ),
      ),
    );
    final s = t.getSize(find.byKey(const Key('chip')));
    expect(s.height, greaterThanOrEqualTo(44));
    expect(s.width, greaterThanOrEqualTo(44));
    await t.tapAt(t.getRect(find.byKey(const Key('chip'))).topLeft + const Offset(20, 1));
    expect(taps, 1);
  });

  test('the minimum is 44', () => expect(kMinTapTarget, 44));
}
