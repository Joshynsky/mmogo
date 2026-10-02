// PaletteAlertDialog: a dialog that follows the palette and the phone's
// light or dark setting (AppTheme itself stays light).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/palette_alert_dialog.dart';

Future<void> _pump(WidgetTester tester, Brightness phone) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: phone),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const PaletteAlertDialog(
                key: Key('pad'),
                title: Text('Title'),
                content: Text('Body'),
                actions: [TextButton(onPressed: null, child: Text('OK'))],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  for (final phone in [Brightness.light, Brightness.dark]) {
    testWidgets('card and text follow the palette on a $phone phone', (tester) async {
      await _pump(tester, phone);
      final palette = AppPalette.of(tester.element(find.byKey(const Key('pad'))));
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, palette.card);
      final body = tester.widget<RichText>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(RichText)).at(1));
      final ink = body.text.style!.color!;
      expect(ink, palette.ink);
      expect(_contrast(ink, palette.card), greaterThan(4.5));
    });
  }
}
