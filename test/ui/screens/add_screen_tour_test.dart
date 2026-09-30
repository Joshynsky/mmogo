// Widget tests for Add's coach tour (lib/ui/screens/add/add_screen.dart +
// lib/ui/widgets/coach_tour.dart), driven through the real AddScreen against
// a minimal always-empty fake Database — the same environment constraint every
// other widget test here documents (a real sqflite_common_ffi Database hangs
// inside testWidgets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/screens/add/add_screen.dart';
import 'package:mpesa_tracker/ui/widgets/coach_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _EmptyDb implements Database {
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
      return [
        {'id': 1, 'code': 'SEND_MONEY', 'display_name': 'Send Money', 'enabled': 1},
        {'id': 2, 'code': 'PAYBILL', 'display_name': 'Paybill', 'enabled': 1},
        {'id': 3, 'code': 'BUY_GOODS', 'display_name': 'Buy Goods', 'enabled': 1},
      ];
    }
    return const [];
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpAdd(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(home: AddScreen(db: _EmptyDb())));
  await _settle(tester);
}

Future<bool?> _storedSeen() async => (await SharedPreferences.getInstance()).getBool('tour_seen_$addTourId');

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(coachTourNextKey));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first visit: a 4-step tour, marked seen only when finished', (tester) async {
    await _pumpAdd(tester);
    expect(find.byKey(coachTourBubbleKey), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);
    expect(find.textContaining('Paste an M-Pesa message'), findsOneWidget);
    expect(await _storedSeen(), isNull);

    await _next(tester);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(find.text('Paid in cash? Switch to Cash.'), findsOneWidget);
    await _next(tester);
    expect(find.text('3 of 4'), findsOneWidget);
    expect(find.byKey(coachTourActionKey), findsOneWidget); // Take me there -> Paid to
    await _next(tester);
    expect(find.text('4 of 4'), findsOneWidget);
    expect(find.byKey(coachTourActionKey), findsNothing);

    await _next(tester); // Done
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(await _storedSeen(), isTrue);
  });

  testWidgets('Skip ends and marks the tour seen', (tester) async {
    await _pumpAdd(tester);
    await tester.tap(find.byKey(coachTourSkipKey));
    await _settle(tester);
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(await _storedSeen(), isTrue);
  });

  testWidgets('already seen: no tour, and the ? button replays it', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_$addTourId': true});
    await _pumpAdd(tester);
    expect(find.byKey(coachTourBubbleKey), findsNothing);

    await tester.tap(find.byKey(const Key('pageHelpButton')));
    await _settle(tester);
    expect(find.byKey(coachTourBubbleKey), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);
  });

  testWidgets('the tour is modal: taps do not reach the page under it', (tester) async {
    await _pumpAdd(tester);
    await tester.tap(find.byKey(const Key('addSrcSeg_CASH')), warnIfMissed: false);
    await _settle(tester);
    // Still on the M-Pesa tab: the paste card is still there.
    expect(find.byKey(const Key('addPasteButton')), findsOneWidget);
  });
}
