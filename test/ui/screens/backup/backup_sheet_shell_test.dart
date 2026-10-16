// 0.1.2 S10b (A9g, A13): the sheet frame: the action row is pinned OUTSIDE the
// scroll area, a long body scrolls inside, and the title names the route.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/backup/backup_sheet_shell.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

Future<void> _pump(WidgetTester t, {required int lines, double scale = 1.0}) async {
  t.view.physicalSize = const Size(400, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BackupSheetShell(
            palette: AppPalette.light,
            title: 'A sheet',
            body: [for (var i = 0; i < lines; i++) Text('Line $i of the body', key: Key('line$i'))],
            actions: SheetActions(
              secondary: OutlinedButton(key: const Key('sec'), onPressed: () {}, child: const Text('Cancel')),
              primary: FilledButton(key: const Key('pri'), onPressed: () {}, child: const Text('Go')),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a long body scrolls; the action row stays on screen and outside the scroll area', (t) async {
    await _pump(t, lines: 80, scale: 1.3);
    expect(t.takeException(), isNull);
    final h = t.view.physicalSize.height;
    expect(t.getSize(find.byType(BackupSheetShell)).height, lessThanOrEqualTo(h * 0.92 + 1), reason: 'capped at 92% of the screen');
    expect(t.getRect(find.byKey(const Key('pri'))).bottom, lessThanOrEqualTo(h));
    expect(t.getRect(find.byKey(const Key('sec'))).bottom, lessThanOrEqualTo(h));
    expect(find.descendant(of: find.byKey(const Key('backupSheetScroll')), matching: find.byKey(const Key('pri'))), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('backupSheetScroll')), matching: find.byKey(const Key('sec'))), findsNothing);
    // The sheet is capped below the whole screen, so the body (not the buttons) scrolls.
    expect(t.getSize(find.byKey(const Key('backupSheetScroll'))).height, lessThan(h));
    await t.drag(find.byKey(const Key('backupSheetScroll')), const Offset(0, -400));
    await t.pump();
    expect(t.getRect(find.byKey(const Key('pri'))).bottom, lessThanOrEqualTo(h), reason: 'buttons do not move with the scroll');
  });

  testWidgets('a short body leaves the sheet as small as its content', (t) async {
    await _pump(t, lines: 1);
    expect(t.getSize(find.byKey(const Key('backupSheetScroll'))).height, lessThan(200));
  });

  testWidgets('the title is a header that also names the route', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, lines: 1);
    expect(t.getSemantics(find.byKey(const Key('backupSheetTitle'))), matchesSemantics(label: 'A sheet', isHeader: true));
    expect(find.bySemanticsLabel('A sheet'), findsWidgets);
    final route = find.byWidgetPredicate((w) => w is Semantics && w.properties.namesRoute == true && w.properties.label == 'A sheet');
    expect(route, findsOneWidget);
    expect(t.widget<Semantics>(route).properties.scopesRoute, isTrue);
    h.dispose();
  });
}
