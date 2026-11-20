// 0.2.1 #10: HighlightRequest is taken once; HighlightPulse outlines for 2 s, steady without animation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';

Widget _host({required bool active, bool still = false, double height = 2000}) => MaterialApp(
  builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: still), child: child!),
  home: Scaffold(
    body: ListView(
      cacheExtent: 4000,
      children: [
        SizedBox(height: height),
        HighlightPulse(active: active, child: const SizedBox(key: Key('row'), height: 60, child: Text('row'))),
        const SizedBox(height: 1500),
      ],
    ),
  ),
);

double _opacity(WidgetTester t) => t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  test('HighlightRequest gives its id once, then nothing', () {
    HighlightRequest.set('a');
    expect(HighlightRequest.take(), 'a');
    expect(HighlightRequest.take(), isNull);
  });

  testWidgets('not active: no outline at all', (tester) async {
    await tester.pumpWidget(_host(active: false));
    expect(find.byKey(const Key('highlightOutline')), findsNothing);
  });

  testWidgets('active: scrolls the row into view, outlines it, and the outline goes after 2 s', (tester) async {
    await tester.pumpWidget(_host(active: true));
    await tester.pump();
    expect(find.byKey(const Key('highlightOutline')), findsOneWidget);
    expect(_opacity(tester), 1);
    final y = tester.getTopLeft(find.byKey(const Key('row'))).dy;
    expect(y, inInclusiveRange(0, 600), reason: 'scrolled to the row (default test screen is 600 high)');
    await tester.pump(kHighlightDuration + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacity(tester), 0);
  });

  testWidgets('alignment 0: the area lands at the top of the viewport', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            cacheExtent: 4000,
            children: [
              const SizedBox(height: 2000),
              HighlightPulse(active: true, alignment: 0, child: const SizedBox(key: Key('row'), height: 60)),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final y = tester.getTopLeft(find.byKey(const Key('row'))).dy;
    expect(y, lessThan(100), reason: 'top of the row near the top of the viewport (below the status area)');
    await tester.pump(kHighlightDuration + const Duration(milliseconds: 600));
  });

  testWidgets('reduced motion: the outline is steady for 2 s, no fade', (tester) async {
    await tester.pumpWidget(_host(active: true, still: true));
    await tester.pump();
    expect(_opacity(tester), 1);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration, Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    expect(_opacity(tester), 0);
  });
}
