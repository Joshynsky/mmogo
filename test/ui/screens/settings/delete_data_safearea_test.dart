// F6 (0.1.2 corrections, R55): the Delete data sheet never runs under the status bar.
// FAKE service, FAKE Back up now flow, FAKE restart: nothing real is touched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/delete_data_harness.dart';
import '../../../support/fake_delete_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const statusBar = 48.0;
  const keyboard = 320.0;
  const screen = Size(400, 800);

  for (final scale in [1.0, 1.6]) {
    testWidgets('R55 text $scale: keyboard up and a 48 dp status bar, the sheet top stays below the status bar, title and "?" whole, both buttons above the keyboard', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, scale: scale, size: screen);
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPadding);
      await openDeleteSheet(tester);
      await tester.ensureVisible(find.byKey(const Key('deleteWordField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteWordField')));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final frame = tester.getRect(find.byKey(const Key('deleteSheetScroll')).hitTestable().first);
      final sheetTop = tester.getTopLeft(find.byKey(const Key('helpSheetTitle'))).dy;
      final title = tester.getRect(find.byKey(const Key('helpSheetTitle')));
      final q = tester.getRect(find.byKey(const Key('deleteHelpButton')));
      expect(frame.top, greaterThan(statusBar), reason: 'the scrolling body is below the status bar');
      expect(sheetTop, greaterThanOrEqualTo(statusBar), reason: 'the title is below the status bar');
      expect(title.top, greaterThanOrEqualTo(statusBar));
      expect(q.top, greaterThanOrEqualTo(statusBar), reason: 'the "?" is below the status bar');
      expect(title.bottom, lessThanOrEqualTo(screen.height - keyboard));
      expect(q.bottom, lessThanOrEqualTo(screen.height - keyboard));
      expect(title.left, greaterThanOrEqualTo(0));
      expect(q.right, lessThanOrEqualTo(screen.width));

      const keyboardTop = 800.0 - keyboard;
      final cancel = tester.getRect(find.byKey(const Key('deleteCancel')));
      final go = tester.getRect(find.byKey(const Key('deleteGo')));
      expect(cancel.bottom, lessThanOrEqualTo(keyboardTop), reason: 'Cancel above the keyboard');
      expect(go.bottom, lessThanOrEqualTo(keyboardTop), reason: 'the red button above the keyboard');
      expect(cancel.top, greaterThanOrEqualTo(statusBar));
      expect(go.top, greaterThanOrEqualTo(statusBar));
      final field = tester.getRect(find.byKey(const Key('deleteWordField')));
      expect(field.bottom, lessThanOrEqualTo(cancel.top), reason: 'the field stays visible above the buttons');
      expect(field.top, greaterThanOrEqualTo(statusBar));
    });
  }
}
