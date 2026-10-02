// B21b: press-and-hold repeat on the Auto-backup + and - buttons. Fake time
// (the widget tester's clock): a tap steps by 1, a hold waits 400 ms then
// repeats every 80 ms, N accelerates to 5 and 10, bounds stop the repeat,
// release stops it, and TalkBack's semantic tap still works.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/backup/hold_step_button.dart';

/// Applies each step to a value the way the page does (clamped) and records
/// every delta it was given.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.start,
    required this.min,
    required this.max,
    required this.direction,
    required this.deltas,
    this.accelerate = false,
    this.enabled = true,
  });

  final int start;
  final int min;
  final int max;
  final int direction;
  final List<int> deltas;
  final bool accelerate;
  final bool enabled;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int value = widget.start;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value', key: const Key('value')),
              HoldStepButton(
                buttonKey: const Key('btn'),
                icon: widget.direction > 0 ? Icons.add_rounded : Icons.remove_rounded,
                tooltip: widget.direction > 0 ? 'More entries' : 'Fewer entries',
                direction: widget.direction,
                value: value,
                min: widget.min,
                max: widget.max,
                enabled: widget.enabled,
                accelerate: widget.accelerate,
                onStep: (d) => setState(() {
                  widget.deltas.add(d);
                  value = (value + d).clamp(widget.min, widget.max);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _value(WidgetTester t) => int.parse(t.widget<Text>(find.byKey(const Key('value'))).data!);

/// Holds the finger down for [ms] in 20 ms frames so every repeat rebuilds.
Future<void> _hold(WidgetTester t, TestGesture g, int ms) async {
  for (var i = 0; i < ms ~/ 20; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

Future<TestGesture> _press(WidgetTester t) => t.startGesture(t.getCenter(find.byKey(const Key('btn'))));

void main() {
  testWidgets('a plain tap steps by exactly 1', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d, accelerate: true));
    await t.tap(find.byKey(const Key('btn')));
    await t.pump(const Duration(seconds: 1));
    expect(d, [1]);
    expect(_value(t), 11);
  });

  testWidgets('minus: a tap steps by -1', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: -1, deltas: d));
    await t.tap(find.byKey(const Key('btn')));
    await t.pump(const Duration(seconds: 1));
    expect(d, [-1]);
  });

  testWidgets('a press shorter than the hold delay is just a tap (one step, no repeat)', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d, accelerate: true));
    final g = await _press(t);
    await _hold(t, g, 300);
    expect(d, isEmpty); // nothing before the 400 ms delay
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(d, [1]);
  });

  testWidgets('hold: nothing at 380 ms, first repeat at 400 ms, then every 80 ms; release stops it and adds no tap',
      (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d));
    final g = await _press(t);
    await _hold(t, g, 380);
    expect(d, isEmpty);
    await _hold(t, g, 40); // 420 ms: the first repeat has fired
    expect(d, [1]);
    await _hold(t, g, 160); // 580 ms: repeats at 480 and 560
    expect(d, [1, 1, 1]);
    await g.up();
    await t.pump(const Duration(milliseconds: 10));
    final after = d.length;
    expect(after, 3); // the release did not count as a tap
    await t.pump(const Duration(seconds: 2));
    expect(d.length, after); // and the repeat is stopped
    expect(_value(t), 13);
  });

  testWidgets('a cancelled pointer also stops the repeat', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d));
    final g = await _press(t);
    await _hold(t, g, 500);
    await g.cancel();
    final n = d.length;
    await t.pump(const Duration(seconds: 2));
    expect(d.length, n);
  });

  testWidgets('N accelerates: steps of 1, then 5 after about 2 s, then 10 after about 4 s', (t) async {
    final d = <int>[];
    // A wide max so the value does not hit the bound before the 10s start.
    await t.pumpWidget(_Harness(start: 1, min: 1, max: 1000, direction: 1, deltas: d, accelerate: true));
    final g = await _press(t);
    await _hold(t, g, 2300); // first repeat at 400 ms; 25 ticks later is about 2.4 s
    expect(d.every((x) => x == 1), isTrue);
    await _hold(t, g, 400);
    expect(d.contains(5), isTrue);
    expect(d.contains(10), isFalse);
    await _hold(t, g, 2000); // 5.1 s in total, past the 4.4 s mark
    expect(d.contains(10), isTrue);
    await g.up();
  });

  testWidgets('K does not accelerate: only steps of 1 however long it is held', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 2, min: 2, max: 20, direction: 1, deltas: d));
    final g = await _press(t);
    await _hold(t, g, 1000);
    expect(d, isNotEmpty);
    expect(d.every((x) => x == 1), isTrue);
    await g.up();
  });

  testWidgets('holding plus stops at the maximum and never goes past it', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 91, min: 1, max: 100, direction: 1, deltas: d, accelerate: true));
    final g = await _press(t);
    await _hold(t, g, 8000);
    expect(_value(t), 100);
    expect(d.fold<int>(0, (a, b) => a + b), 9); // 91 + 9 = 100 exactly
    expect(t.widget<IconButton>(find.byKey(const Key('btn'))).onPressed, isNull);
    final n = d.length;
    await _hold(t, g, 1000);
    expect(d.length, n); // nothing more once the bound is reached
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(d.length, n);
  });

  testWidgets('holding minus stops at the minimum (K floor 2)', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 5, min: 2, max: 20, direction: -1, deltas: d));
    final g = await _press(t);
    await _hold(t, g, 3000);
    expect(_value(t), 2);
    expect(d.fold<int>(0, (a, b) => a + b), -3);
    await g.up();
  });

  testWidgets('a big step is trimmed to the room left (N 97, step 5 would pass 100)', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 60, min: 1, max: 100, direction: 1, deltas: d, accelerate: true));
    final g = await _press(t);
    await _hold(t, g, 9000);
    await g.up();
    expect(_value(t), 100);
    expect(d.every((x) => x <= 10 && x >= 1), isTrue);
    expect(d.fold<int>(0, (a, b) => a + b), 40);
  });

  testWidgets('disabled (paused): a press and a hold do nothing', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d, enabled: false));
    final g = await _press(t);
    await _hold(t, g, 1500);
    await g.up();
    expect(d, isEmpty);
    expect(t.widget<IconButton>(find.byKey(const Key('btn'))).onPressed, isNull);
  });

  testWidgets('accessibility: the label stays and a semantic tap (TalkBack double-tap) steps by 1', (t) async {
    final handle = t.ensureSemantics();
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d, accelerate: true));
    expect(find.byTooltip('More entries'), findsOneWidget);
    final node = t.getSemantics(find.byTooltip('More entries'));
    final data = node.getSemanticsData();
    expect('${data.label} ${data.tooltip}', contains('More entries'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    t.semantics.tap(find.semantics.byAction(SemanticsAction.tap).first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(d, [1]);
    handle.dispose();
  });

  testWidgets('disposing while held cancels the timers (no pending timer left)', (t) async {
    final d = <int>[];
    await t.pumpWidget(_Harness(start: 10, min: 1, max: 100, direction: 1, deltas: d));
    final g = await _press(t);
    await _hold(t, g, 600);
    await t.pumpWidget(const SizedBox());
    await g.up();
    await t.pump(const Duration(seconds: 1));
  });
}
