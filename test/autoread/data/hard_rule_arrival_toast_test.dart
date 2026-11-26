@Tags(['autoread'])
library;

// 0.2.2 item 2, redesign U-UNDO (sign-off F-3, D-U): the no-tap message "{Name}, Ksh {amount} recorded as
// {Category}" with Undo; Undo of a no-tap entry shows the top pill "Undone. {Name} stays on Auto-record."; Undo of
// a tapped (soft, queued Yes) entry shows today's undo text on the same top pill. The name never carries a digit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/hard_rule_arrival_toast.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/data/queued_yes_toast.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:mmogo/ui/widgets/tap_target.dart';

const QueuedYesRecorded _auto =
    QueuedYesRecorded(itemId: 'a', rowId: 5, amountCents: 45000, categoryId: 7, automatic: true);
const QueuedYesRecorded _soft = QueuedYesRecorded(itemId: 'b', rowId: 6, amountCents: 50000, categoryId: 7);

final RegExp _digit = RegExp(r'[0-9]');

Future<void> _app(WidgetTester t,
    {ThemeData? theme, TextDirection dir = TextDirection.ltr, double textScale = 1, Size? size}) async {
  if (size != null) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(MaterialApp(
    navigatorKey: appNavigatorKey,
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Directionality(textDirection: dir, child: child!),
    ),
    home: const Scaffold(body: SizedBox()),
  ));
}

Future<void> _slideIn(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// The top pill's text widgets (the message line).
Iterable<String> _pillTexts(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '');

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() {
    debugAutoRecordUiOverride = null;
    PillToast.dismissNow();
  });

  group('the plain name', () {
    test('drops the masked number, a bare number and any word with a digit', () {
      expect(autoArrivalPlainName('Alice Wanjiru 0722***456'), 'Alice Wanjiru');
      expect(autoArrivalPlainName('  Alice   Wanjiru  '), 'Alice Wanjiru');
      expect(autoArrivalPlainName('0722123456'), isNull);
      expect(autoArrivalPlainName('***456'), isNull);
      expect(autoArrivalPlainName(''), isNull);
      expect(autoArrivalPlainName(null), isNull);
      expect(autoArrivalPlainName('Mama Mboga'), 'Mama Mboga');
    });
  });

  group('no-tap message (hard) + Undo', () {
    testWidgets('signed line with the plain name, the amount and the category; Undo on the pill', (t) async {
      await _app(t);
      showAutoArrivalToasts([_auto], (_) async {},
          nameOf: (_) => 'Alice Wanjiru 0722***456', categoryOf: (_) => 'Family/Friends');
      await _slideIn(t);
      expect(find.text(hardAutoArrived('Alice Wanjiru', 45000, 'Family/Friends')), findsOneWidget);
      expect(find.text('Alice Wanjiru, Ksh 450 recorded as Family/Friends'), findsOneWidget);
      expect(find.text(kQueuedYesUndo), findsOneWidget);
      // the name part carries no digit and no mask; only the amount has digits
      final line = _pillTexts(t).firstWhere((s) => s.contains('recorded as'));
      expect(line.split(',').first, 'Alice Wanjiru');
      expect(line.split(',').first.contains(_digit), isFalse);
      expect(line.contains('***'), isFalse);
      expect(line.contains('0722'), isFalse);
    });

    testWidgets('Undo: moves the row once, then the top pill says the person stays on Auto-record', (t) async {
      final undone = <int>[];
      await _app(t);
      showAutoArrivalToasts([_auto], (e) async => undone.add(e.rowId),
          nameOf: (_) => 'Alice Wanjiru 0722***456', categoryOf: (_) => 'Family/Friends');
      await _slideIn(t);
      await t.tap(find.text(kQueuedYesUndo));
      await t.pumpAndSettle();
      expect(undone, [5]);
      expect(find.text(hardUndoStays('Alice Wanjiru')), findsOneWidget);
      expect(find.text('Undone. Alice Wanjiru stays on Auto-record.'), findsOneWidget);
      expect(find.text(kQueuedYesUndone), findsNothing, reason: 'the hard path has its own signed line');
      expect(find.text(kQueuedYesUndo), findsNothing, reason: 'the undo pill has no second Undo');
      expect(PillToast.isShowing, isTrue);
      // the undo pill carries no digit at all
      expect(_pillTexts(t).where((s) => s.contains('stays on')).single.contains(_digit), isFalse);
      // a top pill, not a bottom snackbar
      expect(find.byType(SnackBar), findsNothing);
      expect(t.getTopLeft(find.text(hardUndoStays('Alice Wanjiru'))).dy, lessThan(200));
    });

    testWidgets('no names from the caller: the W2 placeholders, never a number', (t) async {
      await _app(t);
      showAutoArrivalToasts([_auto], (_) async {}, nameOf: (_) => '0722***456');
      await _slideIn(t);
      final line = _pillTexts(t).firstWhere((s) => s.contains('recorded as'));
      expect(line, contains('[PM to write: name'));
      expect(line, contains('[PM to write: category'));
      expect(line, contains('Ksh 450'));
      expect(line.contains('0722'), isFalse);
    });

    testWidgets('one pill per entry: the newer replaces the older', (t) async {
      await _app(t);
      showAutoArrivalToasts([
        _auto,
        const QueuedYesRecorded(itemId: 'c', rowId: 9, amountCents: 12000, categoryId: 3, automatic: true),
      ], (_) async {}, nameOf: (e) => e.rowId == 5 ? 'Alice' : 'Bob', categoryOf: (_) => 'Food');
      await _slideIn(t);
      expect(find.text(hardAutoArrived('Bob', 12000, 'Food')), findsOneWidget);
      expect(find.text(hardAutoArrived('Alice', 45000, 'Food')), findsNothing);
    });

    test('no overlay shows nothing and does not throw', () {
      showAutoArrivalToasts([_auto], (_) async {}, nameOf: (_) => 'Alice', categoryOf: (_) => 'Food');
    });
  });

  group('tapped entry (soft, queued Yes) + Undo', () {
    testWidgets('Undo shows the top pill with today\'s undo text, not the Auto-record line', (t) async {
      final undone = <int>[];
      await _app(t);
      showQueuedYesToasts([_soft], (e) async => undone.add(e.rowId));
      await _slideIn(t);
      await t.tap(find.text(kQueuedYesUndo));
      await t.pumpAndSettle();
      expect(undone, [6]);
      expect(find.text(kQueuedYesUndone), findsOneWidget);
      expect(find.textContaining('stays on Auto-record'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(t.getTopLeft(find.text(kQueuedYesUndone)).dy, lessThan(200));
    });
  });

  group('quality bar', () {
    for (final dark in [false, true]) {
      testWidgets('200% text on a 320 px screen, RTL, ${dark ? 'dark' : 'light'}: no overflow, 44 px Undo, live region',
          (t) async {
        final handle = t.ensureSemantics();
        await _app(t,
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            dir: TextDirection.rtl,
            textScale: 2,
            size: const Size(320, 700));
        showAutoArrivalToasts([_auto], (_) async {},
            nameOf: (_) => 'Alice Wanjiru', categoryOf: (_) => 'Family/Friends');
        await _slideIn(t);
        expect(t.takeException(), isNull);
        final undo = t.getSize(find.ancestor(of: find.text(kQueuedYesUndo), matching: find.byType(TextButton)));
        expect(undo.width, greaterThanOrEqualTo(kMinTapTarget));
        expect(undo.height, greaterThanOrEqualTo(kMinTapTarget));
        expect(
          find.byWidgetPredicate((w) => w is Semantics && (w.properties.liveRegion ?? false)),
          findsWidgets,
        );
        await t.tap(find.text(kQueuedYesUndo));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(hardUndoStays('Alice Wanjiru')), findsOneWidget);
        handle.dispose();
      });
    }
  });
}
