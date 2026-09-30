// Widget tests for lib/ui/widgets/hint_bubble.dart (T19) — the shared
// contextual hint host, exercised in isolation (both positioning modes)
// against the Phase 5 PM's binding rules: no layout space shown or hidden,
// Got-it-only dismissal (tapping elsewhere never marks it seen), per-hint
// seen-flag persistence, non-blocking, and an anchored bubble never
// covering its anchor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/widgets/hint_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _anchorKey = Key('anchorButton');
const _belowKey = Key('belowButton');
const _farKey = Key('farButton');

/// A ListView whose first item is an anchor button (optionally wrapped in a
/// CompositedTransformTarget) followed by other real controls, hosted in a
/// HintOverlayHost — the same shape Add/Analytics use.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.hintId,
    this.anchored = true,
    this.enabled = true,
    this.showAnchor = true,
    this.onAnchorTap,
    this.onFarTap,
  });

  final String hintId;
  final bool anchored;
  final bool enabled;
  final bool showAnchor;
  final VoidCallback? onAnchorTap;
  final VoidCallback? onFarTap;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    Widget anchor = SizedBox(
      height: 48,
      child: OutlinedButton(key: _anchorKey, onPressed: widget.onAnchorTap ?? () {}, child: const Text('Anchor')),
    );
    if (widget.anchored) anchor = CompositedTransformTarget(link: _link, child: anchor);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Top bar')),
        body: HintOverlayHost(
          hintId: widget.hintId,
          message: 'A helpful hint',
          anchorLink: widget.anchored ? _link : null,
          enabled: widget.enabled,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.showAnchor) anchor,
              const SizedBox(height: 12),
              ElevatedButton(key: _belowKey, onPressed: () {}, child: const Text('Below')),
              const SizedBox(height: 300),
              ElevatedButton(key: _farKey, onPressed: widget.onFarTap ?? () {}, child: const Text('Far')),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _bubble(String id) => find.byKey(ValueKey('hintBubble_$id'));
Finder _gotIt(String id) => find.byKey(Key('hintGotIt_$id'));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<bool?> _storedSeen(String id) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('hint_seen_$id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows while unseen; an already-seen hint never shows', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'h1'));
    await _settle(tester);
    expect(_bubble('h1'), findsOneWidget);
    expect(find.text('A helpful hint'), findsOneWidget);

    SharedPreferences.setMockInitialValues({'hint_seen_h2': true});
    await tester.pumpWidget(const _Harness(hintId: 'h2'));
    await _settle(tester);
    expect(_bubble('h2'), findsNothing);
  });

  testWidgets('occupies no layout space: every control is at the identical position shown vs. hidden',
      (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'layout'));
    await _settle(tester);
    expect(_bubble('layout'), findsOneWidget);
    final anchorShown = tester.getRect(find.byKey(_anchorKey));
    final belowShown = tester.getRect(find.byKey(_belowKey));
    final farShown = tester.getRect(find.byKey(_farKey));

    await tester.tap(_gotIt('layout'));
    await _settle(tester);
    expect(_bubble('layout'), findsNothing);
    expect(tester.getRect(find.byKey(_anchorKey)), anchorShown);
    expect(tester.getRect(find.byKey(_belowKey)), belowShown);
    expect(tester.getRect(find.byKey(_farKey)), farShown);
  });

  testWidgets('anchored mode: the bubble sits below the anchor and never covers it', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'anch'));
    await _settle(tester);
    final anchor = tester.getRect(find.byKey(_anchorKey));
    final bubble = tester.getRect(_bubble('anch'));
    expect(bubble.top, moreOrLessEquals(anchor.bottom + 8));
    expect(bubble.overlaps(anchor), isFalse);
    expect(bubble.left, moreOrLessEquals(anchor.left));
  });

  testWidgets('anchored mode keeps tracking the anchor when the content scrolls', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'scroll'));
    await _settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -40));
    await _settle(tester);
    final anchor = tester.getRect(find.byKey(_anchorKey));
    final bubble = tester.getRect(_bubble('scroll'));
    expect(bubble.top, moreOrLessEquals(anchor.bottom + 8));
  });

  testWidgets('fixed mode floats at the fixed offset just below the top bar', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'fixed', anchored: false));
    await _settle(tester);
    final body = tester.getRect(find.byType(HintOverlayHost));
    final bubble = tester.getRect(_bubble('fixed'));
    expect(bubble.top, moreOrLessEquals(body.top + 16));
    expect(bubble.left, moreOrLessEquals(body.left + 16));
  });

  testWidgets('tapping elsewhere, dragging, or waiting never dismisses or marks it seen', (tester) async {
    var farTaps = 0;
    await tester.pumpWidget(_Harness(hintId: 'passive', onFarTap: () => farTaps++));
    await _settle(tester);

    // Tap a control outside the bubble.
    await tester.tap(find.byKey(_farKey));
    await _settle(tester);
    // Tap empty space outside the bubble.
    await tester.tapAt(const Offset(5, 590));
    await _settle(tester);
    // Swipe on the bubble itself.
    await tester.drag(_bubble('passive'), const Offset(300, 0));
    await _settle(tester);
    // Wait (no auto-timeout).
    await tester.pump(const Duration(minutes: 5));

    expect(farTaps, 1);
    expect(_bubble('passive'), findsOneWidget);
    expect(await _storedSeen('passive'), isNull);
  });

  testWidgets('non-blocking: controls outside the bubble (incl. the anchor itself) work while shown',
      (tester) async {
    var anchorTaps = 0;
    var farTaps = 0;
    await tester.pumpWidget(
      _Harness(hintId: 'nb', onAnchorTap: () => anchorTaps++, onFarTap: () => farTaps++),
    );
    await _settle(tester);
    expect(_bubble('nb'), findsOneWidget);

    await tester.tap(find.byKey(_anchorKey)); // default warnIfMissed: would fail if something covered it
    await tester.tap(find.byKey(_farKey));
    await _settle(tester);
    expect(anchorTaps, 1);
    expect(farTaps, 1);
    expect(_bubble('nb'), findsOneWidget);
  });

  testWidgets('Got it hides it and persists the seen flag for THAT hint id only', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'persist_a'));
    await _settle(tester);
    await tester.tap(_gotIt('persist_a'));
    await _settle(tester);

    expect(_bubble('persist_a'), findsNothing);
    expect(await _storedSeen('persist_a'), isTrue);
    expect(await _storedSeen('persist_b'), isNull);

    // A fresh host (e.g. next visit) for the same id stays hidden...
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const _Harness(hintId: 'persist_a'));
    await _settle(tester);
    expect(_bubble('persist_a'), findsNothing);

    // ...while a different hint id is unaffected.
    await tester.pumpWidget(const _Harness(hintId: 'persist_b'));
    await _settle(tester);
    expect(_bubble('persist_b'), findsOneWidget);
  });

  testWidgets('enabled:false hides it without marking seen; it returns when re-enabled', (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'sup', enabled: false));
    await _settle(tester);
    expect(_bubble('sup'), findsNothing);
    expect(await _storedSeen('sup'), isNull);

    await tester.pumpWidget(const _Harness(hintId: 'sup'));
    await _settle(tester);
    expect(_bubble('sup'), findsOneWidget);
  });

  testWidgets('anchored mode with no anchor built: not shown (never floated at a guessed spot), not marked seen',
      (tester) async {
    await tester.pumpWidget(const _Harness(hintId: 'noanchor', showAnchor: false));
    await _settle(tester);
    expect(find.text('A helpful hint').hitTestable(), findsNothing);
    expect(await _storedSeen('noanchor'), isNull);

    await tester.pumpWidget(const _Harness(hintId: 'noanchor'));
    await _settle(tester);
    expect(find.text('A helpful hint').hitTestable(), findsOneWidget);
  });
}
