// A 100-character category name must never overflow a chip list on a 360 dp wide screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/add/category_chips.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/flat_classification_picker.dart';
import 'package:mmogo/ui/widgets/mpesa_classification_picker.dart';
import 'package:mmogo/ui/widgets/withdrawal_use_block.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/restore_test_db.dart';

final String _unbroken = ('Very%26long%2Fname%27quotes%2701234567' * 4).substring(0, 100);
final String _spaced = ('Very long category name with several words ' * 3).substring(0, 100);

void main() {
  assert(_unbroken.length == 100 && _spaced.length == 100);
  final names = {'unbroken': _unbroken, 'with spaces': _spaced};

  Future<void> narrow(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget host(Widget child) => MaterialApp(theme: AppTheme.theme, home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))));

  for (final e in names.entries) {
    testWidgets('withdrawal use chips, 100 chars ${e.key}: no overflow', (t) async {
      await narrow(t);
      await t.pumpWidget(host(WithdrawalUseBlock(
        palette: AppPalette.light,
        choices: [WdChoice(1, e.value), const WdChoice(2, 'Rent')],
        selectedId: 1,
        sentence: 's',
        onChanged: (_) {},
        onCreate: (_) async => const WdCreateResult.error('x'),
      )));
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('wdChip-1')), findsOneWidget);
    });

    testWidgets('Add category chips, 100 chars ${e.key}: no overflow', (t) async {
      await narrow(t);
      late Database db;
      await t.runAsync(() async {
        db = await openTestDb();
        await addClass(db, 'SEND_MONEY', e.value);
      });
      await t.pumpWidget(host(CategoryChips(
        db: db,
        sourceType: 'CASH',
        counterpartyKey: '',
        counterpartyDisplayName: '',
        selectedId: null,
        selectedName: null,
        onSelected: (a, b) {},
        autoApplyChecked: false,
        onAutoApplyChanged: (_) {},
      )));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(find.byKey(const Key('addCategoryNewButton')), findsOneWidget);
      expect(find.text(e.value), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() => db.close());
    });

    testWidgets('flat picker rows, 100 chars ${e.key}: no overflow', (t) async {
      await narrow(t);
      late Database db;
      await t.runAsync(() async {
        db = await openTestDb();
        await addClass(db, 'SEND_MONEY', e.value);
      });
      await t.pumpWidget(host(FlatClassificationPicker(db: db, onClassificationSelected: (_) {})));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(find.text(e.value), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() => db.close());
    });

    testWidgets('group picker rows, 100 chars ${e.key}: no overflow', (t) async {
      await narrow(t);
      late Database db;
      await t.runAsync(() async {
        db = await openTestDb();
        await addClass(db, 'SEND_MONEY', e.value);
      });
      await t.pumpWidget(host(MpesaClassificationPicker(db: db, groupCode: 'SEND_MONEY', onClassificationSelected: (_) {})));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(find.text(e.value), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() => db.close());
    });
  }
}
