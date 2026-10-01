// B3: length limits on Manage classifications. The create field and the
// rename dialog cut a 101-character name at 100 (counter hidden); a saved name
// that is already longer still loads in full. This screen has no receiver /
// label field (those limits are tested in add/add_screen_limits_test.dart).
// Uses a minimal fake Database (a real sqflite_common_ffi one hangs in
// testWidgets here; see manage_classifications_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/manage_classifications_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDb implements Database {
  final longName = 'L' * 130;

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
      ];
    }
    if (table == 'classifications') {
      final active = where!.contains('active = 1');
      return active ? [{'id': 101, 'group_id': 1, 'name': longName, 'active': 1}] : [];
    }
    throw UnsupportedError('unexpected table $table');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create field: 101 characters are cut at 100; an existing 130-character name loads in full',
      (tester) async {
    final db = _FakeDb();
    await tester.pumpWidget(MaterialApp(home: ManageClassificationsScreen(db: db)));
    await _settle(tester);

    expect(find.text(db.longName), findsOneWidget); // not truncated on load

    await tester.enterText(find.byType(TextField), 'a' * 101);
    await _settle(tester);

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, 100);
    expect(find.text('100/100'), findsNothing);
  });
}
