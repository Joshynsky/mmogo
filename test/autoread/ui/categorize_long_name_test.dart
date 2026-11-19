@Tags(['autoread'])
library;

// A 100-character category name must not overflow the Categorize sheet chips at 360 dp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/category_choices_fake.dart';
import '../../support/waiting_fakes.dart';

void main() {
  final unbroken = ('Very%26long%2Fname%27quotes%2701234567' * 4).substring(0, 100);
  final spaced = ('Very long category name with several words ' * 3).substring(0, 100);
  for (final e in {'unbroken': unbroken, 'with spaces': spaced}.entries) {
    testWidgets('categorize chips, 100 chars ${e.key}: no overflow', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final at = DateTime.utc(2026, 10, 18, 10, 0);
      final item = WaitingItem(id: heldIdFor(1), kind: WaitingKind.waitingCategory, heldAt: at, parsed: sampleFields(0, at));
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(body: CategorizeSheet(item: item, choices: FakeCategoryChoices([e.value, 'Rent']), onSave: (_) async {})),
      ));
      await t.pumpAndSettle();
      expect(find.text(e.value), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
