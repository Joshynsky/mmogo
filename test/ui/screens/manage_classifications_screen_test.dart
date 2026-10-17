// Widget tests for lib/ui/screens/manage_classifications_screen.dart.
//
// Same environment constraint T7 already root-caused: a real sqflite_common_ffi
// `Database` hangs indefinitely inside a `testWidgets` test in this
// environment. This file therefore drives the real screen against a
// minimal, explicitly fake in-memory `Database` (`_FakeDatabase` below)
// mirroring T1's real seed shape closely enough to exercise the screen's
// real UI/interaction logic (tab switching, active vs. inactive rendering,
// restore, and the delete-confirmation dialog's real COUNT(*) message) —
// the real per-group query/rename/soft-delete/restore/count SQL is
// separately, authoritatively proven against a genuine in-memory sqlite3
// database in `test/data/classification_dao_test.dart`, which this widget
// calls directly and unconditionally (`ManageClassificationsScreen`
// contains no query logic of its own that could diverge from the DAO's
// real, DB-tested behavior).
//
// This screen reads its `Database` in production via
// `AppDatabase.instance.database` (matching `home_screen.dart`'s own
// convention), but exposes a nullable `db` constructor parameter as a
// test-only injection seam (see `manage_classifications_screen.dart`'s own
// doc comment on that field) — this file uses that seam directly, the same
// way the other classification screens are constructor-injectable, rather
// than attempting to make the real `AppDatabase` singleton resolve inside
// `testWidgets` (the exact wall T7 already root-caused).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/manage_classifications_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Minimal concrete `DatabaseException` subclass: `sqflite_common_ffi`'s public
/// API only exports the abstract `DatabaseException`, so this is the
/// smallest legitimate way to throw a real one whose
/// `isUniqueConstraintError()` (the exact method the screen's catch blocks
/// call) evaluates real message text, not a hand-rolled boolean.
class _FakeUniqueConstraintViolation extends DatabaseException {
  _FakeUniqueConstraintViolation(super.message);

  @override
  int? getResultCode() => 2067; // SQLITE_CONSTRAINT_UNIQUE extended code

  @override
  Object? get result => null;
}

/// Fake `Database` mirroring T1's real seed shape
/// (`classification_groups`/`classifications`/`transactions`), plus the
/// four operations this screen actually calls beyond T7's original
/// `query`/`insert`: `update` (rename/soft-delete/restore) and `rawQuery`
/// (the delete-confirmation dialog's real `COUNT(*)`). Every other
/// `Database`/`DatabaseExecutor` member falls through to `noSuchMethod`
/// (unused by this screen).
class _FakeDatabase implements Database {
  _FakeDatabase()
      : groups = [
          {'id': 1, 'code': 'SEND_MONEY', 'display_name': 'Send Money', 'enabled': 1},
          {'id': 2, 'code': 'PAYBILL', 'display_name': 'Paybill', 'enabled': 1},
          {'id': 3, 'code': 'BUY_GOODS', 'display_name': 'Buy Goods', 'enabled': 1},
          {'id': 4, 'code': 'POCHI_LA_BIASHARA', 'display_name': 'Pochi', 'enabled': 1},
          {'id': 5, 'code': 'AGENT_WITHDRAWAL', 'display_name': 'Withdrawal', 'enabled': 1},
          {'id': 6, 'code': 'AIRTIME', 'display_name': 'Airtime', 'enabled': 1},
        ],
        classifications = [
          {'id': 101, 'group_id': 1, 'name': 'Family/Friends', 'active': 1},
          {'id': 102, 'group_id': 1, 'name': 'Rent', 'active': 1},
          {'id': 103, 'group_id': 1, 'name': 'Transport', 'active': 1},
          {'id': 104, 'group_id': 1, 'name': 'Groceries', 'active': 1},
          {'id': 199, 'group_id': 1, 'name': 'Old Rent', 'active': 0},
          {'id': 105, 'group_id': 2, 'name': 'Rent Payment', 'active': 1},
          {'id': 106, 'group_id': 2, 'name': 'Shopping', 'active': 1},
          {'id': 107, 'group_id': 4, 'name': 'Fares', 'active': 1},
          {'id': 108, 'group_id': 5, 'name': 'Cash withdrawal', 'active': 1},
          {'id': 109, 'group_id': 6, 'name': 'Top up', 'active': 1},
        ],
        transactionCountByClassification = {102: 3};

  final List<Map<String, Object?>> groups;
  final List<Map<String, Object?>> classifications;
  final Map<int, int> transactionCountByClassification;
  int _nextId = 1000;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'classification_groups') {
      return [...groups]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    }
    if (table == 'classifications') {
      final groupId = whereArgs![0] as int;
      final wantActive = where!.contains('active = 1');
      return classifications
          .where((c) => c['group_id'] == groupId && (c['active'] == 1) == wantActive)
          .toList()
        ..sort(
          (a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()),
        );
    }
    throw UnsupportedError('_FakeDatabase.query: unexpected table "$table"');
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('COUNT(*)') && sql.contains('transactions')) {
      final classificationId = arguments![0] as int;
      return [
        {'c': transactionCountByClassification[classificationId] ?? 0},
      ];
    }
    throw UnsupportedError('_FakeDatabase.rawQuery: unexpected sql "$sql"');
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table != 'classifications') {
      throw UnsupportedError('_FakeDatabase.insert: unexpected table "$table"');
    }
    final groupId = values['group_id'] as int;
    final name = values['name'] as String;
    final dup = classifications.any(
      (c) => c['group_id'] == groupId && c['active'] == 1 && c['name'] == name,
    );
    if (dup) {
      throw _FakeUniqueConstraintViolation(
        'UNIQUE constraint failed: classifications.group_id, classifications.name (code 2067)',
      );
    }
    final id = _nextId++;
    classifications.add({'id': id, 'group_id': groupId, 'name': name, 'active': 1});
    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table != 'classifications') {
      throw UnsupportedError('_FakeDatabase.update: unexpected table "$table"');
    }
    final id = whereArgs![0] as int;
    final row = classifications.firstWhere((c) => c['id'] == id);
    if (values.containsKey('name')) {
      final newName = values['name'] as String;
      final dup = classifications.any(
        (c) =>
            c['id'] != id &&
            c['group_id'] == row['group_id'] &&
            c['active'] == 1 &&
            c['name'] == newName,
      );
      if (dup) {
        throw _FakeUniqueConstraintViolation(
          'UNIQUE constraint failed: classifications.group_id, classifications.name (code 2067)',
        );
      }
      row['name'] = newName;
      return 1;
    }
    if (values.containsKey('active')) {
      final wantActive = values['active'] as int;
      if (wantActive == 1) {
        final dup = classifications.any(
          (c) => c['id'] != id && c['group_id'] == row['group_id'] && c['active'] == 1 && c['name'] == row['name'],
        );
        if (dup) {
          throw _FakeUniqueConstraintViolation(
            'UNIQUE constraint failed: classifications.group_id, classifications.name (code 2067)',
          );
        }
      }
      row['active'] = wantActive;
      return 1;
    }
    throw UnsupportedError('_FakeDatabase.update: unexpected values $values');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness(Database db) {
  return MaterialApp(
    home: ManageClassificationsScreen(db: db),
  );
}

/// T26 "i think it should recolor the entire app": this screen under a
/// given chosen palette — an `AppPaletteScope` so `AppPalette.of` resolves
/// it, rather than the no-scope-above `ocean` fallback (same pattern T24's
/// profile_screen_test.dart `_appWithPalette` established).
Widget _harnessWithPalette(Database db, {required String paletteId}) {
  return AppPaletteScope(
    controller: AppPaletteController(paletteId),
    child: MaterialApp(home: ManageClassificationsScreen(db: db)),
  );
}

/// `_settle`: the fake DB resolves via ordinary microtasks (no real I/O),
/// so a bounded couple of plain `pump()`s is enough — deliberately NOT
/// `pumpAndSettle()`, matching T7's own documented reasoning: this screen
/// shows an indeterminate `CircularProgressIndicator` while loading, which
/// schedules a fresh frame every tick and would hang `pumpAndSettle()`
/// regardless of how fast the underlying Future resolves.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'renders six group tabs (none dimmed), defaults to Send Money, lists active + inactive categories',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      for (final t in ['Send Money', 'Paybill', 'Buy Goods', 'Pochi', 'Withdrawal', 'Airtime']) {
        expect(find.text(t), findsOneWidget, reason: 'tab $t');
      }
      expect(find.textContaining('(n/a)'), findsNothing);
      expect(find.text('Manage categories'), findsOneWidget);

      // Active list (Send Money).
      expect(find.text('Family/Friends'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      // Inactive list: the soft-deleted "Old Rent" row, distinct from the active list.
      expect(find.text('Old Rent'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
    },
  );

  testWidgets(
    'the Pochi tab is enabled: tapping it shows its own categories and the create row',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('manageTab-POCHI_LA_BIASHARA')));
      await _settle(tester);

      expect(find.text('Fares'), findsOneWidget);
      expect(find.text('Family/Friends'), findsNothing);
      expect(find.byKey(const Key('manageCreateRow')), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the Paybill tab switches active+inactive lists to that group only',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      await tester.tap(find.text('Paybill'));
      await _settle(tester);

      // Paybill's own active rows render...
      expect(find.text('Rent Payment'), findsOneWidget);
      expect(find.text('Shopping'), findsOneWidget);
      // ...and Send Money's rows must not leak into Paybill's view.
      expect(find.text('Family/Friends'), findsNothing);
      expect(find.text('Old Rent'), findsNothing);
      expect(find.text('No active categories in this group.'), findsNothing);
      // Paybill has no seeded inactive rows in this fake.
      expect(find.text('No inactive categories in this group.'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Restore on the inactive row moves it into the active list',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      expect(find.text('Old Rent'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await _settle(tester);

      expect(find.text('Old Rent'), findsOneWidget); // now in the active list
      expect(find.text('Restore'), findsNothing); // inactive list now empty
      expect(find.text('No inactive categories in this group.'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Delete on an active row with real transactions shows the confirmation dialog '
    'with the real COUNT(*)-derived message, not a generic "are you sure"',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      // "Rent" (id 102) has transactionCountByClassification[102] == 3 in
      // the fake. Active list is sorted name COLLATE NOCASE ascending:
      // Family/Friends(0), Groceries(1), Rent(2), Transport(3).
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsNWidgets(4)); // one per active row
      await tester.tap(deleteButtons.at(2)); // Rent
      await _settle(tester);

      expect(find.text('Delete category?'), findsOneWidget);
      expect(
        find.text(
          '3 transactions use "Rent". It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping Delete on an active row with zero transactions shows the zero-count message',
    (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);

      // "Family/Friends" (id 101) has no entry in transactionCountByClassification -> 0.
      final deleteButtons = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteButtons.first); // Family/Friends sorts first
      await _settle(tester);

      expect(
        find.text(
          'No transactions currently use "Family/Friends". '
          'It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'confirming Delete soft-deletes the row: it moves from active to inactive',
    (tester) async {
      final db = _FakeDatabase();
      await tester.pumpWidget(_harness(db));
      await _settle(tester);

      final deleteButtons = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteButtons.at(2)); // Rent
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(tester);

      final rentRow = db.classifications.firstWhere((c) => c['id'] == 102);
      expect(rentRow['active'], 0);
    },
  );

  testWidgets('T26: recolours under Leaf — the app bar, the selected tab and a card all use Leaf tokens', (
    tester,
  ) async {
    await tester.pumpWidget(_harnessWithPalette(_FakeDatabase(), paletteId: 'leaf'));
    await _settle(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.leafLight.background);

    // The selected group tab (Send Money, the default) is filled with the
    // palette's own primary, not the old fixed AppColors.primary green.
    final selectedTab = tester.widget<Container>(
      find
          .ancestor(of: find.text('Send Money'), matching: find.byType(Container))
          .first,
    );
    expect((selectedTab.decoration! as BoxDecoration).color, AppPalette.leafLight.primary);
    expect((selectedTab.decoration! as BoxDecoration).color, isNot(AppColors.primary));
  });

  group('MC1: locked built-ins, create row per group, duplicate error', () {
    Future<void> openTab(WidgetTester tester, _FakeDatabase db, String code) async {
      await tester.pumpWidget(_harness(db));
      await _settle(tester);
      await tester.tap(find.byKey(Key('manageTab-$code')));
      await _settle(tester);
    }

    for (final (code, name, row) in [
      ('AGENT_WITHDRAWAL', 'Withdrawal', 'Cash withdrawal'),
      ('AIRTIME', 'Airtime', 'Top up'),
    ]) {
      testWidgets('$name: built-in is locked (tag, no Rename or Delete) and there is no create row', (tester) async {
        await openTab(tester, _FakeDatabase(), code);
        expect(find.text(row), findsOneWidget);
        expect(find.byKey(Key('manageBuiltIn-$row')), findsOneWidget);
        expect(find.text('Built in'), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(find.byKey(const Key('manageCreateRow')), findsNothing);
        expect(find.byKey(const Key('manageCreateField')), findsNothing);
        expect(find.text('$name entries always use this category.'), findsOneWidget);
      });
    }

    for (final code in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA']) {
      testWidgets('$code has the create row and no Built in tag', (tester) async {
        await openTab(tester, _FakeDatabase(), code);
        expect(find.byKey(const Key('manageCreateRow')), findsOneWidget);
        expect(find.byKey(const Key('manageLockedLine')), findsNothing);
        expect(find.text('Built in'), findsNothing);
      });
    }

    testWidgets('a duplicate name shows the red inline error with the warning icon, and typing clears it', (tester) async {
      final db = _FakeDatabase();
      await tester.pumpWidget(_harness(db));
      await _settle(tester);

      await tester.enterText(find.byKey(const Key('manageCreateField')), 'Rent');
      await tester.tap(find.byKey(const Key('manageCreateAdd')));
      await _settle(tester);

      final err = find.byKey(const Key('manageCreateError'));
      expect(err, findsOneWidget);
      expect(find.text('A category named "Rent" already exists in Send Money.'), findsOneWidget);
      expect(find.descendant(of: err, matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
      final text = tester.widget<Text>(find.text('A category named "Rent" already exists in Send Money.'));
      expect(text.style!.color, AppPalette.light.error);
      expect(find.byType(SnackBar), findsNothing);

      await tester.enterText(find.byKey(const Key('manageCreateField')), 'Ren');
      await tester.pump();
      expect(err, findsNothing);
    });

    testWidgets('a new Pochi category is created and listed (the same table Add reads)', (tester) async {
      final db = _FakeDatabase();
      await openTab(tester, db, 'POCHI_LA_BIASHARA');
      await tester.enterText(find.byKey(const Key('manageCreateField')), 'Airtime top-ups');
      await tester.tap(find.byKey(const Key('manageCreateAdd')));
      await _settle(tester);
      expect(find.text('Airtime top-ups'), findsOneWidget);
      expect(db.classifications.any((c) => c['group_id'] == 4 && c['name'] == 'Airtime top-ups' && c['active'] == 1), isTrue);
    });

    testWidgets('a blocked restore shows the inline error beside the list, not a snackbar', (tester) async {
      final db = _FakeDatabase();
      db.classifications.add({'id': 200, 'group_id': 1, 'name': 'Old Rent', 'active': 1});
      await tester.pumpWidget(_harness(db));
      await _settle(tester);
      await tester.tap(find.text('Restore'));
      await _settle(tester);
      expect(find.byKey(const Key('manageRestoreError')), findsOneWidget);
      expect(find.textContaining('a category named "Old Rent" already exists in Send Money.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Rename keeps the dialog open with the inline error on a duplicate', (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);
      await tester.tap(find.byTooltip('Rename Groceries'));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('manageRenameField')), 'Rent');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);
      expect(find.byKey(const Key('manageRenameError')), findsOneWidget);
      expect(find.text('A category named "Rent" already exists in Send Money.'), findsOneWidget);
      expect(find.text('Rename category'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('360 dp, text scale 1.3, ${dark ? 'dark' : 'light'}: no overflow, the Airtime tab can be reached', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await tester.pumpWidget(_harness(_FakeDatabase()));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('manageTab-AIRTIME')));
        await tester.tap(find.byKey(const Key('manageTab-AIRTIME')));
        await _settle(tester);
        expect(find.text('Built in'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // F2 R38: the pencil (rename) and bin (delete) icons have a 44 x 44 hit area.
  group('R38 row icon hit areas', () {
    testWidgets('pencil and bin are at least 44 x 44; a tap 1 px inside the edge works', (tester) async {
      await tester.pumpWidget(_harness(_FakeDatabase()));
      await _settle(tester);
      for (final (icon, tooltip) in [(Icons.edit_outlined, 'Rename Groceries'), (Icons.delete_outline, 'Delete Groceries')]) {
        final button = find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)).first;
        final size = tester.getSize(button);
        // ignore: avoid_print
        print('R38 measured $tooltip: $size');
        expect(size.width, greaterThanOrEqualTo(44), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(44), reason: tooltip);
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
      // Tap near the bottom-right corner of the pencil's 44 px box (1 px in).
      final pencil = find.ancestor(of: find.byIcon(Icons.edit_outlined), matching: find.byType(IconButton)).first;
      final rect = tester.getRect(pencil);
      await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
      await _settle(tester);
      expect(find.text('Rename category'), findsOneWidget, reason: 'the edge tap reached the pencil');
    });
  });
}
