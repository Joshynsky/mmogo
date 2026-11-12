// 0.2.0 loose end: the Undo toast must time out (it lingered 35+ minutes on a
// phone because a SnackBar with an action persists by default).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';

void main() {
  test('the auto-recorded toast does not persist and times out', () {
    final sb = autoRecordedSnackBar(
      AutoRecorded(rowId: 1, amountCents: 500, at: DateTime(2026, 11, 11)),
      () {},
    );
    expect(sb.persist, isFalse);
    expect(sb.duration, const Duration(seconds: kAutoRecordedToastSeconds));
    expect(sb.action, isNotNull);
  });

  testWidgets('it disappears after its duration on screen', (t) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await t.pumpWidget(MaterialApp(scaffoldMessengerKey: key, home: const Scaffold(body: SizedBox())));
    key.currentState!.showSnackBar(autoRecordedSnackBar(
      AutoRecorded(rowId: 1, amountCents: 500, at: DateTime(2026, 11, 11)),
      () {},
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Recorded as Airtime, Ksh 5.'), findsOneWidget);
    await t.pump(const Duration(seconds: 9));
    await t.pumpAndSettle();
    expect(find.text('Recorded as Airtime, Ksh 5.'), findsNothing);
  });
}
