import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';

void main() {
  test('phoneEnding: last 3 digits for Send Money only', () {
    expect(phoneEnding(ReceiverType.sendMoney, '0717571997'), '997');
    expect(phoneEnding(ReceiverType.sendMoney, '0729345350'), '350');
    expect(phoneEnding(ReceiverType.sendMoney, 'MERAB'), isNull);
    expect(phoneEnding(ReceiverType.buyGoods, '0717571997'), isNull);
    expect(phoneEnding(ReceiverType.payBill, 'ABC#123456'), isNull);
  });

  testWidgets('two numbers of one name show as different rows by their endings', (tester) async {
    Widget row(String key) => MaterialApp(
          home: Scaffold(
            body: LevelsPersonRow(
              person: LevelPerson(
                  type: ReceiverType.sendMoney, key: key, name: 'MERAB OPANY', level: RuleLevel.suggested),
              onLevelTap: () {},
            ),
          ),
        );
    await tester.pumpWidget(row('0717571997'));
    expect(find.textContaining('…997', findRichText: true), findsOneWidget);
    await tester.pumpWidget(row('0729345350'));
    expect(find.textContaining('…350', findRichText: true), findsOneWidget);
  });
}
