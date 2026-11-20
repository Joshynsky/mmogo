// §WIDGET.PILL_TOAST tests: size to content, top placement, Undo once, auto-dismiss, replacement, swipe up,
// reduced motion, big text on a narrow screen, semantics.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';

Future<void> _host(WidgetTester t, {double scale = 1, double width = 390, bool reduce = false, EdgeInsets pad = EdgeInsets.zero}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 800);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    navigatorKey: appNavigatorKey,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduce,
        padding: pad,
        viewPadding: pad,
      ),
      child: child!,
    ),
    home: const Scaffold(body: Center(child: Text('PAGE'))),
  ));
}

/// The pill's own Material (nearest Material above the message text).
Finder _pillOf(String msg) => find.ancestor(of: find.text(msg), matching: find.byType(Material)).first;

/// Shows a toast and lets it slide in (the first pump starts the animation).
Future<void> _show(WidgetTester t, String msg, {String? action, VoidCallback? onAction}) async {
  PillToast.show(msg, actionLabel: action, onAction: onAction);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(PillToast.dismissNow);

  testWidgets('size to content: short is smaller than long; long wraps within the cap', (t) async {
    await _host(t);
    const longMsg = 'Recorded Ksh 500 from your Yes on the alert. It was a long message that has to wrap onto lines. '
        'Recorded Ksh 500 from your Yes on the alert. It was a long message that has to wrap onto lines.';
    await _show(t, 'Saved');
    final short = t.getSize(_pillOf('Saved'));
    await _show(t, longMsg);
    final long = t.getSize(_pillOf(longMsg));
    expect(short.width, lessThan(150));
    expect(long.width, greaterThan(short.width));
    expect(long.width, lessThanOrEqualTo(390 * 0.9 + 0.01));
    expect(long.height, greaterThan(short.height));
    expect(t.takeException(), isNull);
  });

  testWidgets('floats top-centre under the safe area, not over the status bar', (t) async {
    await _host(t, pad: const EdgeInsets.only(top: 40));
    await _show(t, 'Saved');
    final r = t.getRect(_pillOf('Saved'));
    expect(r.top, greaterThanOrEqualTo(40));
    expect(r.center.dx, closeTo(195, 1));
  });

  testWidgets('Undo fires once, dismisses the toast', (t) async {
    await _host(t);
    var n = 0;
    await _show(t, 'Recorded', action: 'Undo', onAction: () => n++);
    expect(t.getSize(find.widgetWithText(TextButton, 'Undo')).height, greaterThanOrEqualTo(44));
    await t.tap(find.text('Undo'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(n, 1);
    expect(find.text('Recorded'), findsNothing);
    expect(PillToast.isShowing, isFalse);
  });

  testWidgets('an action that shows a new toast keeps the new one', (t) async {
    await _host(t);
    await _show(t, 'One', action: 'Undo', onAction: () => PillToast.show('Two'));
    await t.tap(find.text('Undo'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('stays 6 s, then slides away and is gone', (t) async {
    await _host(t);
    await _show(t, 'Saved', action: 'Undo', onAction: () {});
    await t.pump(const Duration(milliseconds: 5000));
    expect(find.text('Saved'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsNothing);
    expect(PillToast.isShowing, isFalse);
  });

  testWidgets('a second toast replaces the first', (t) async {
    await _host(t);
    await _show(t, 'First');
    await _show(t, 'Second');
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('swipe up dismisses', (t) async {
    await _host(t);
    await _show(t, 'Saved');
    await t.drag(find.text('Saved'), const Offset(0, -60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('reduced motion: appears and disappears with no slide', (t) async {
    await _host(t, reduce: true);
    PillToast.show('Saved');
    await t.pump();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.ancestor(of: find.text('Saved'), matching: find.byType(SlideTransition)), findsNothing);
    await t.pump(const Duration(seconds: 6, milliseconds: 100));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('text scale 2.0 on 390 px: no overflow, Undo still reachable', (t) async {
    await _host(t, scale: 2.0);
    await _show(t, 'Recorded Ksh 500 from your Yes on the alert.', action: 'Undo', onAction: () {});
    expect(t.takeException(), isNull);
    expect(t.getRect(_pillOf('Recorded Ksh 500 from your Yes on the alert.')).right, lessThanOrEqualTo(390));
    // 6 s at scale 1 becomes longer at scale 2: still there after 7 s
    await t.pump(const Duration(seconds: 7));
    expect(find.text('Undo'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('semantics: live region message, action is a button', (t) async {
    final h = t.ensureSemantics();
    await _host(t);
    await _show(t, 'Recorded Ksh 5.', action: 'Undo', onAction: () {});
    final msg = t.getSemantics(find.text('Recorded Ksh 5.'));
    expect(msg.label, 'Recorded Ksh 5.');
    expect(msg.flagsCollection.isLiveRegion, isTrue);
    final undo = t.getSemantics(find.text('Undo'));
    expect(undo.label, 'Undo');
    expect(undo.flagsCollection.isButton, isTrue);
    expect(undo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    h.dispose();
  });

  testWidgets('no app on screen: show does nothing', (t) async {
    PillToast.show('Saved');
    expect(PillToast.isShowing, isFalse);
  });
}
