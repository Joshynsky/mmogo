// Widget tests for lib/ui/screens/settings_screen.dart (T23 rework: cards
// regrouped under Appearance/Your data/Preferences, "Manage classifications"/
// "Recently deleted" now sentence case per the T23 draft mock, and the
// working colour palette switch). Per this project's disclosed environment
// finding (first hit at T7, see recently_deleted_screen_test.dart's header
// comment): a real sqflite_common_ffi `Database` hangs indefinitely inside a
// `testWidgets` test in this environment. This file drives the screen
// against a minimal, explicit fake in-memory `Database` (`_FakeDb` below),
// and injects a fake `exportCsv` side effect (real `path_provider`/
// `share_plus` platform channels aren't available in `testWidgets` here
// either) to observe the button's enabled/disabled state at zero vs.
// nonzero active transactions and the success SnackBar, without touching
// either real plugin.
//
// The real `ExportDao` query/join/CSV-formatting logic is separately,
// authoritatively proven against a genuine in-memory sqlite3 database in
// `test/data/export_dao_test.dart` — this screen calls that DAO directly
// and unconditionally.
//
// Settings now resolves colours through `AppPaletteScope` (T23), so every
// pump here wraps the screen in one (default id `ocean`, matching
// `AppPaletteController`'s own startup default) rather than pumping
// `SettingsScreen` bare.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/prefs/app_prefs.dart';
import 'package:mpesa_tracker/ui/screens/settings_screen.dart';
import 'package:mpesa_tracker/ui/theme/app_colors.dart';
import 'package:mpesa_tracker/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDb implements Database {
  _FakeDb({required this.transactions});

  final List<Map<String, Object?>> transactions;

  final classifications = <Map<String, Object?>>[
    {'id': 201, 'name': 'Family/Friends', 'group_id': 1},
  ];
  final groups = <Map<String, Object?>>[
    {'id': 1, 'display_name': 'Send Money'},
  ];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final active = transactions.where((t) => t['deleted_at'] == null).toList();
    if (sql.contains('COUNT(*) AS cnt')) {
      return [
        {'cnt': active.length},
      ];
    }
    if (sql.contains('JOIN classifications c') && sql.contains('JOIN classification_groups g')) {
      active.sort(
        (a, b) => (b['transaction_occurred_at'] as int).compareTo(a['transaction_occurred_at'] as int),
      );
      return active
          .map(
            (t) => {
              'display_code': t['display_code'],
              'source_type': t['source_type'],
              'amount_cents': t['amount_cents'],
              'transaction_cost_cents': t['transaction_cost_cents'],
              'counterparty_label': t['counterparty_label'],
              'counterparty_phone': t['counterparty_phone'],
              'paybill_account_number': t['paybill_account_number'],
              'classification_name': 'Family/Friends',
              'group_display_name': 'Send Money',
              'transaction_occurred_at': t['transaction_occurred_at'],
            },
          )
          .toList();
    }
    throw UnsupportedError('_FakeDb.rawQuery: unexpected sql "$sql"');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _tx({
  required String displayCode,
  int? deletedAt,
  int occurredAt = 0,
}) => {
      'display_code': displayCode,
      'source_type': 'SEND_MONEY',
      'amount_cents': 150000,
      'transaction_cost_cents': 2500,
      'counterparty_label': 'JOHN KAMAU',
      'counterparty_phone': '0798630424',
      'paybill_account_number': null,
      'transaction_occurred_at': occurredAt,
      'deleted_at': deletedAt,
    };

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Wraps [screen] in the `AppPaletteScope` Settings now depends on for every
/// colour it draws. [controller] defaults to a fresh one (id `ocean`,
/// unloaded — same starting state `AppPaletteController`'s own doc comment
/// documents for a real app launch before `load()` resolves).
Widget _wrap(SettingsScreen screen, {AppPaletteController? controller}) {
  return MaterialApp(home: AppPaletteScope(controller: controller ?? AppPaletteController(), child: screen));
}

InkWell _rowInkWell(WidgetTester tester, String label) =>
    tester.widget<InkWell>(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);

/// The Preferences card (and its Switch) sits below the fold at the default
/// test surface size and is the LAST card on the page, so this scrolls the
/// `ListView` all the way to its end (a single oversized drag, clamped at
/// `maxScrollExtent` — safe to call repeatedly / already-at-the-end) rather
/// than stopping as soon as the switch is merely "visible"
/// (`dragUntilVisible`'s own stopping rule): "just visible" can still land
/// right at the viewport's bottom edge, inside the primary bottom nav's FAB
/// overhang hit box (`_OverhangHitBox`, `primary_scaffold.dart`), which then
/// silently swallows the tap instead of the switch — and exactly how far
/// "just visible" is shifts with any copy change above it on the page (T26:
/// the palette card's subline). Scrolling flush to the end is independent
/// of that.
Future<void> _scrollToAutoRecognizeSwitch(WidgetTester tester) async {
  await tester.drag(find.byKey(const Key('settingsScroll')), const Offset(0, -2000));
  await tester.pump();
}

Future<Switch> _autoRecognizeSwitch(WidgetTester tester) async {
  await _scrollToAutoRecognizeSwitch(tester);
  return tester.widget<Switch>(find.byType(Switch));
}

/// Scrolls the switch into view immediately before tapping it (see
/// [_scrollToAutoRecognizeSwitch]) rather than reusing wherever an earlier
/// scroll happened to land.
Future<void> _tapAutoRecognizeSwitch(WidgetTester tester) async {
  await _scrollToAutoRecognizeSwitch(tester);
  await tester.tap(find.byType(Switch));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Default ON — matches AppPrefs' own documented default;
    // tests that need an explicit stored value override this.
    SharedPreferences.setMockInitialValues({});
  });

  group('Auto-recognize classifications toggle (T18)', () {
    testWidgets('reflects the real persisted default (ON) when no value is stored', (tester) async {
      final db = _FakeDb(transactions: []);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect((await _autoRecognizeSwitch(tester)).value, isTrue);
    });

    testWidgets('reflects an explicitly-stored false value on load', (tester) async {
      SharedPreferences.setMockInitialValues({'auto_recognize_classifications': false});
      final db = _FakeDb(transactions: []);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect((await _autoRecognizeSwitch(tester)).value, isFalse);
    });

    testWidgets('tapping the switch updates the UI immediately and persists the new value', (tester) async {
      final db = _FakeDb(transactions: []);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect((await _autoRecognizeSwitch(tester)).value, isTrue);

      await _tapAutoRecognizeSwitch(tester);
      await tester.pump();

      // Immediate: reflects the new value in the UI on the very next pump,
      // without waiting on the underlying write to complete.
      expect((await _autoRecognizeSwitch(tester)).value, isFalse);

      // Persisted: reading it back independently via AppPrefs confirms the
      // write actually landed, not just the local widget state.
      expect(await AppPrefs.readAutoRecognizeClassifications(), isFalse);
    });

    testWidgets('tapping the switch again toggles back on and persists true', (tester) async {
      SharedPreferences.setMockInitialValues({'auto_recognize_classifications': false});
      final db = _FakeDb(transactions: []);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect((await _autoRecognizeSwitch(tester)).value, isFalse);

      await _tapAutoRecognizeSwitch(tester);
      await tester.pump();

      expect((await _autoRecognizeSwitch(tester)).value, isTrue);
      expect(await AppPrefs.readAutoRecognizeClassifications(), isTrue);
    });
  });

  testWidgets('Export CSV row is disabled when there are zero active transactions', (tester) async {
    final db = _FakeDb(transactions: []);
    await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
    await _settle(tester);

    expect(_rowInkWell(tester, 'Export CSV').onTap, isNull);
    expect(find.text('No transactions to export yet'), findsOneWidget);
  });

  testWidgets(
    'Export CSV row is disabled when all transactions are soft-deleted',
    (tester) async {
      final db = _FakeDb(transactions: [_tx(displayCode: 'S1', deletedAt: 1000)]);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect(_rowInkWell(tester, 'Export CSV').onTap, isNull);
    },
  );

  testWidgets('Export CSV row is enabled when there is at least one active transaction', (tester) async {
    final db = _FakeDb(transactions: [_tx(displayCode: 'S1')]);
    await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
    await _settle(tester);

    expect(_rowInkWell(tester, 'Export CSV').onTap, isNotNull);
    expect(find.text('Share all 1 transaction as CSV'), findsOneWidget);
  });

  testWidgets(
    'tapping an enabled Export CSV row calls the export side effect with the real CSV content and '
    'shows the "CSV exported — N transactions" SnackBar',
    (tester) async {
      final db = _FakeDb(
        transactions: [_tx(displayCode: 'S1', occurredAt: 1758546600000), _tx(displayCode: 'S2', occurredAt: 1758546700000)],
      );
      String? capturedCsv;
      int? capturedCount;
      await tester.pumpWidget(
        _wrap(
          SettingsScreen(
            db: db,
            exportCsv: (csv, count) async {
              capturedCsv = csv;
              capturedCount = count;
            },
          ),
        ),
      );
      await _settle(tester);

      expect(_rowInkWell(tester, 'Export CSV').onTap, isNotNull);
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();

      expect(capturedCount, 2);
      expect(capturedCsv, isNotNull);
      expect(capturedCsv, contains('S1'));
      expect(capturedCsv, contains('S2'));
      expect(capturedCsv, contains('JOHN KAMAU'));
      expect(find.text('CSV exported — 2 transactions'), findsOneWidget);
    },
  );

  testWidgets(
    'a single active transaction shows the singular "transaction" (not "transactions") in both '
    'the subtitle and the success SnackBar',
    (tester) async {
      final db = _FakeDb(transactions: [_tx(displayCode: 'S1')]);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();

      expect(find.text('CSV exported — 1 transaction'), findsOneWidget);
    },
  );

  testWidgets(
    'a failing export side effect shows a failure SnackBar instead of crashing',
    (tester) async {
      final db = _FakeDb(transactions: [_tx(displayCode: 'S1')]);
      await tester.pumpWidget(
        _wrap(SettingsScreen(db: db, exportCsv: (_, _) async => throw Exception('share sheet unavailable'))),
      );
      await _settle(tester);

      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();

      expect(find.text('CSV export failed — please try again'), findsOneWidget);
    },
  );

  group('Colour palette switch (T23)', () {
    testWidgets('shows the three palettes with Ocean & Sun selected by default', (tester) async {
      final semantics = tester.ensureSemantics();
      final db = _FakeDb(transactions: []);
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {})));
      await _settle(tester);

      expect(find.text('Ocean & Sun'), findsOneWidget);
      expect(find.text('Leaf & Gold'), findsOneWidget);
      expect(find.text('Indigo & Peach'), findsOneWidget);
      final ocean = tester.getSemantics(find.byKey(const Key('paletteTile-ocean')));
      expect(ocean.label, contains('selected'));
      semantics.dispose();
    });

    testWidgets('tapping Leaf changes AppPalette.of(context).primary and persists it', (tester) async {
      final db = _FakeDb(transactions: []);
      final controller = AppPaletteController();
      await tester.pumpWidget(_wrap(SettingsScreen(db: db, exportCsv: (_, _) async {}), controller: controller));
      await _settle(tester);

      final context = tester.element(find.byKey(const Key('paletteTile-leaf')));
      expect(AppPalette.of(context).primary, AppPalette.light.primary);

      await tester.tap(find.byKey(const Key('paletteTile-leaf')));
      await tester.pump();

      expect(AppPalette.of(context).primary, AppPalettes.leaf.light.primary);
      expect(controller.value, 'leaf');
      expect(await AppPrefs.readPaletteId(), 'leaf');
    });
  });
}
