// Widget tests for Add's T19 contextual hint (lib/ui/screens/add/
// add_screen.dart + lib/ui/widgets/hint_bubble.dart), driven through the
// real AddScreen against a minimal always-empty fake Database — same
// environment constraint every other widget test here documents (a real
// sqflite_common_ffi Database hangs inside testWidgets). Nothing under test
// depends on row content.
//
// T27 moved the hint's anchor from the retired "Parse M-Pesa message"
// button to the new "Paste M-Pesa SMS" card (paste_card.dart) — the hint
// id/message/dismiss/anchoring RULES themselves are unchanged, just what
// they point at.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/screens/add/add_screen.dart';
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

const _pasteBtn = Key('addPasteButton');
const _mpesaToggle = Key('addSrcSeg_MPESA');
const _cashToggle = Key('addSrcSeg_CASH');
const _gotIt = Key('addHintGotIt');
final _bubble = find.byKey(const ValueKey('hintBubble_$addHintId'));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpAdd(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(home: AddScreen(db: _EmptyDb())));
  await _settle(tester);
}

Future<bool?> _storedSeen() async =>
    (await SharedPreferences.getInstance()).getBool('hint_seen_$addHintId');

bool _visible(Finder f) => f.hitTestable().evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first visit: hint shown with the real current labels', (tester) async {
    await _pumpAdd(tester);
    expect(find.text(addHintMessage), findsOneWidget);
    expect(_visible(_bubble), isTrue);
    expect(find.descendant(of: find.byKey(_pasteBtn), matching: find.text('Parse M-Pesa message')), findsOneWidget);
    expect(find.descendant(of: find.byKey(_cashToggle), matching: find.text('Cash')), findsOneWidget);
    expect(addHintMessage, contains('"Parse M-Pesa message"'));
    expect(addHintMessage, contains('Cash'));
  });

  testWidgets('never covers the paste card or the M-Pesa/Cash switcher', (tester) async {
    await _pumpAdd(tester);
    final bubble = tester.getRect(_bubble);
    final paste = tester.getRect(find.byKey(_pasteBtn));
    final mpesa = tester.getRect(find.byKey(_mpesaToggle));
    final cash = tester.getRect(find.byKey(_cashToggle));
    expect(bubble.overlaps(paste), isFalse);
    expect(bubble.overlaps(mpesa), isFalse);
    expect(bubble.overlaps(cash), isFalse);
    expect(bubble.top, moreOrLessEquals(paste.bottom + 8));
  });

  testWidgets('occupies no layout space: the paste card and switcher do not move when it is dismissed', (tester) async {
    await _pumpAdd(tester);
    final pasteShown = tester.getRect(find.byKey(_pasteBtn));
    final cashShown = tester.getRect(find.byKey(_cashToggle));

    await tester.tap(find.byKey(_gotIt));
    await _settle(tester);
    expect(find.text(addHintMessage), findsNothing);
    expect(tester.getRect(find.byKey(_pasteBtn)), pasteShown);
    expect(tester.getRect(find.byKey(_cashToggle)), cashShown);
    expect(await _storedSeen(), isTrue);
  });

  testWidgets('non-blocking: the paste card works while the hint is shown, and does not mark it seen', (tester) async {
    await _pumpAdd(tester);
    await tester.tap(find.byKey(_pasteBtn));
    await _settle(tester);
    expect(find.byKey(const Key('addPasteTextField')), findsOneWidget);
    expect(await _storedSeen(), isNull);
  });

  testWidgets('Cash tab: hint hidden (no paste card to point at) but NOT marked seen; back on M-Pesa it returns',
      (tester) async {
    await _pumpAdd(tester);
    await tester.tap(find.byKey(_cashToggle)); // switcher usable while hint shown
    await _settle(tester);
    expect(find.byKey(_pasteBtn), findsNothing);
    expect(_visible(_bubble), isFalse);
    expect(await _storedSeen(), isNull);

    await tester.tap(find.byKey(_mpesaToggle));
    await _settle(tester);
    expect(_visible(_bubble), isTrue);
    expect(tester.getRect(_bubble).overlaps(tester.getRect(find.byKey(_pasteBtn))), isFalse);
  });

  testWidgets('already seen: hint never shows', (tester) async {
    SharedPreferences.setMockInitialValues({'hint_seen_$addHintId': true});
    await _pumpAdd(tester);
    expect(find.text(addHintMessage), findsNothing);
  });
}
