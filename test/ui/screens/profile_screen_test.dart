// Widget tests for lib/ui/screens/profile_screen.dart (T17). Per this
// project's disclosed environment finding (see settings_screen_test.dart /
// recently_deleted_screen_test.dart headers), a real sqflite_common_ffi
// `Database` hangs inside `testWidgets` here, so the screen is driven
// against a minimal fake `Database` that answers only
// LocalDataSummaryDao.summary's aggregate query. The real SQL (COUNT/MIN/
// MAX, deleted_at IS NULL) is proven against genuine sqlite3 in
// test/data/local_data_summary_dao_test.dart.
//
// Also covers the Home-greeting integration gap T17 closes: editing the
// name on Profile (pushed on top of a live Home) and pressing back shows
// the new greeting immediately, not after a relaunch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_info.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/screens/profile_screen.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDb implements Database {
  _FakeDb({required this.occurredAt});

  /// transaction_occurred_at of each ACTIVE row (the fake models the DAO's
  /// own already-filtered aggregate result).
  final List<int> occurredAt;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('COUNT(*) AS tx_count') && sql.contains('deleted_at IS NULL')) {
      return [
        {
          'tx_count': occurredAt.length,
          'min_occurred_at': occurredAt.isEmpty ? null : occurredAt.reduce((a, b) => a < b ? a : b),
          'max_occurred_at': occurredAt.isEmpty ? null : occurredAt.reduce((a, b) => a > b ? a : b),
        },
      ];
    }
    throw UnsupportedError('_FakeDb.rawQuery: unexpected sql "$sql"');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _app(Database db) => MaterialApp(home: ProfileScreen(db: db));

/// T24: [ProfileScreen] under a given palette id + phone brightness — an
/// `AppPaletteScope` (so `AppPalette.of` resolves the chosen palette rather
/// than the no-scope-above `ocean` fallback) plus a `MediaQuery` override
/// for the phone's brightness (the widget-test binding's own platform
/// brightness is always light).
Widget _appWithPalette(Database db, {required String paletteId, required Brightness brightness}) {
  return AppPaletteScope(
    controller: AppPaletteController(paletteId),
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
        child: child!,
      ),
      home: ProfileScreen(db: db),
    ),
  );
}

/// T20: with no display name, Home's greeting is just the time of day
/// ("Good morning" / "Good afternoon" / "Good evening"; no "Welcome back").
final _noNameGreeting = find.textContaining(RegExp(r'^Good (morning|afternoon|evening)$'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  // Welcome's timer waits for its first frame to be on screen; the
  // widget-test binding has no rasteriser, so treat "built" as "presented"
  // (see test/ui/screens/onboarding_flow_test.dart for the real gate).
  setUp(() => welcomeFirstFramePresented = waitForFrameBuilt);
  tearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);

  testWidgets('renders app info with the AppInfo version and no dev placeholder', (tester) async {
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [])));
    await _settle(tester);

    expect(find.text(AppInfo.name), findsOneWidget);
    expect(find.text(AppInfo.displayVersion), findsOneWidget);
    expect(find.textContaining('T17'), findsNothing);
    // Secondary chrome: back arrow, no bottom nav.
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Paid to'), findsNothing);
  });

  testWidgets('empty database: 0 transactions, "No data yet", storage "—"', (tester) async {
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [])));
    await _settle(tester);

    expect(find.text('0 transactions'), findsOneWidget);
    expect(find.text('No data yet'), findsOneWidget);
    // Fake (non-file) database -> size unknown -> em dash, not a crash.
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('populated database: count and formatted date range', (tester) async {
    final a = DateTime(2026, 3, 4, 9).millisecondsSinceEpoch;
    final b = DateTime(2026, 9, 22, 18).millisecondsSinceEpoch;
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [b, a])));
    await _settle(tester);

    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.text('04 Mar 2026 – 22 Sep 2026'), findsOneWidget);
  });

  testWidgets('T24: dark MediaQuery + Leaf renders the Leaf dark background', (tester) async {
    await tester.pumpWidget(
      _appWithPalette(_FakeDb(occurredAt: []), paletteId: 'leaf', brightness: Brightness.dark),
    );
    await _settle(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.leafDark.background);
  });

  testWidgets('singular "1 transaction"', (tester) async {
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [DateTime(2026, 9, 1).millisecondsSinceEpoch])));
    await _settle(tester);
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('01 Sep 2026 – 01 Sep 2026'), findsOneWidget);
  });

  testWidgets('pre-fills the field with the stored display name', (tester) async {
    SharedPreferences.setMockInitialValues({AppPrefs.keyUserDisplayName: 'Amina'});
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [])));
    await _settle(tester);

    final field = tester.widget<TextField>(find.byKey(const Key('profile-name-field')));
    expect(field.controller!.text, 'Amina');
    expect(field.maxLength, 30);
  });

  testWidgets('Save trims and persists the name, with confirmation', (tester) async {
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [])));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('profile-name-field')), '  Joshua  ');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppPrefs.keyUserDisplayName), 'Joshua');
    expect(find.text('Saved — Home will greet you as Joshua'), findsOneWidget);
  });

  testWidgets('saving empty/whitespace removes the key rather than storing ""', (tester) async {
    SharedPreferences.setMockInitialValues({AppPrefs.keyUserDisplayName: 'Amina'});
    await tester.pumpWidget(_app(_FakeDb(occurredAt: [])));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('profile-name-field')), '   ');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AppPrefs.keyUserDisplayName), isFalse);
    expect(await AppPrefs.readUserDisplayName(), isNull);
    expect(find.text('Name cleared — Home will greet you without a name'), findsOneWidget);
  });

  testWidgets('writeUserDisplayName bumps the revision notifier on success', (tester) async {
    final before = AppPrefs.userDisplayNameRevision.value;
    expect(await AppPrefs.writeUserDisplayName('Zawadi'), isTrue);
    expect(AppPrefs.userDisplayNameRevision.value, before + 1);
    expect(await AppPrefs.readUserDisplayName(), 'Zawadi');
    expect(await AppPrefs.writeUserDisplayName(null), isTrue);
    expect(AppPrefs.userDisplayNameRevision.value, before + 2);
    expect(await AppPrefs.readUserDisplayName(), isNull);
  });

  testWidgets('Home greeting refreshes on return from Profile after editing the name '
      '(no relaunch)', (tester) async {
    // Real app + real routes: Profile is pushed via PrimaryScaffold's
    // top-right icon on top of a still-mounted Home, exactly as on device.
    // (Home's own DB load hangs in testWidgets here, which is irrelevant:
    // the greeting is the AppBar title and is loaded independently.)
    // T16: the app now launches on Welcome and routes to Home only once
    // onboarding is complete, so mark it complete and step past Welcome's
    // ~3s auto-continue + the route transition (durations, not
    // pumpAndSettle -- see below).
    SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true});
    await tester.pumpWidget(const MpesaTrackerApp());
    await tester.pump(welcomeDuration);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_noNameGreeting, findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile-name-field')), 'Joshua');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    // pump with durations, not pumpAndSettle: Home's body spinner never
    // settles while its (hung-in-test) DB load is pending.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining(RegExp(r'^Good (morning|afternoon|evening) Joshua,$')), findsOneWidget);
    expect(_noNameGreeting, findsNothing);

    // And clearing it goes back to the fallback.
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name-field')), '');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_noNameGreeting, findsOneWidget);
  });
}
