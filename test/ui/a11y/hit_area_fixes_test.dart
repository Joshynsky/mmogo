// S11b: hit-area fixes that no matrix subject reaches by itself.
//   - The Analytics "moved to Recently Deleted" toast: Undo is a 44 px target
//     (was 32), and the bar keeps its height (its padding went from 7 to 1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics/toast.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

void main() {
  testWidgets('toast Undo is at least 44 x 44, taps, and the toast is no taller than before', (t) async {
    var undone = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AnalyticsToast(palette: AppPalette.light, message: 'Moved to Recently Deleted', onUndo: () => undone++),
          ),
        ),
      ),
    );
    final undo = t.getSize(find.byKey(const Key('analyticsUndo')));
    expect(undo.height, greaterThanOrEqualTo(44));
    expect(undo.width, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byKey(const Key('analyticsToast'))).height, lessThanOrEqualTo(48), reason: 'it was 46 before the fix');
    await t.tap(find.byKey(const Key('analyticsUndo')));
    expect(undone, 1);
  });
}
