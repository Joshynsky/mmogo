// 0.2.0 S8 — the Paybill ACCOUNTS block: pages of 5, sideways, dots, "Page n of N", no Next / Previous.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/ui/screens/paid_to/accounts_block.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

PaidToRecipient _group(int accounts) {
  PaidToGrouping.paybillByName = true;
  final r = groupPaidTo([
    for (var i = 0; i < accounts; i++)
      PaidToPayment(
        sourceType: 'PAYBILL',
        amountCents: (1000 + i) * 100,
        feeCents: 0,
        occurredAt: DateTime(2026, 10, 5, 10),
        classificationName: 'Bills',
        label: 'DIRECT PAY 04',
        account: '70000${i.toString().padLeft(2, '0')}',
      ),
  ]).single;
  PaidToGrouping.paybillByName = false;
  return r;
}

Widget _host(PaidToRecipient r, {double width = 360}) => MaterialApp(
  key: UniqueKey(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: PaidToAccountsBlock(key: UniqueKey(), palette: AppPalette.light, recipient: r),
      ),
    ),
  ),
);

void main() {
  testWidgets('25 accounts: 5 pages, "Page 1 of 5", 5 dots, no Next / Previous', (t) async {
    await t.pumpWidget(_host(_group(25)));
    expect(find.byKey(const Key('paidToAccountsPageLabel')), findsOneWidget);
    expect(find.textContaining('Page 1 of 5'), findsOneWidget);
    for (var k = 0; k < 5; k++) {
      expect(find.byKey(Key('paidToAccountsDot-$k')), findsOneWidget);
    }
    expect(find.byKey(const Key('paidToAccountsDot-5')), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Previous'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('25 under this name'), findsOneWidget);
    expect(find.text('25 accounts · 25 payments'), findsOneWidget);
  });

  testWidgets('a sideways swipe moves to page 2 and snaps; the label follows', (t) async {
    await t.pumpWidget(_host(_group(25)));
    await t.drag(find.byKey(const Key('paidToAccountsPager')), const Offset(-250, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Page 2 of 5'), findsOneWidget);
    final sv = t.widget<SingleChildScrollView>(find.byKey(const Key('paidToAccountsPager')));
    expect(sv.controller!.offset, closeTo(360, 0.6)); // snapped to a whole page
  });

  testWidgets('a short swipe snaps back to page 1', (t) async {
    await t.pumpWidget(_host(_group(25)));
    await t.drag(find.byKey(const Key('paidToAccountsPager')), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Page 1 of 5'), findsOneWidget);
    final sv = t.widget<SingleChildScrollView>(find.byKey(const Key('paidToAccountsPager')));
    expect(sv.controller!.offset, closeTo(0, 0.6));
  });

  testWidgets('a dot goes to its page (the no-swipe way)', (t) async {
    await t.pumpWidget(_host(_group(25)));
    await t.tap(find.byKey(const Key('paidToAccountsDot-3')));
    await t.pumpAndSettle();
    expect(find.textContaining('Page 4 of 5'), findsOneWidget);
  });

  testWidgets('24 accounts: last page holds 4; 26: 6 pages', (t) async {
    await t.pumpWidget(_host(_group(24)));
    expect(find.textContaining('Page 1 of 5'), findsOneWidget);
    expect(find.byKey(const Key('paidToAccountsPage-4')), findsOneWidget);
    await t.pumpWidget(_host(_group(26)));
    expect(find.textContaining('Page 1 of 6'), findsOneWidget);
  });

  testWidgets('5 or fewer accounts: listed, no pager, no dots, no page label', (t) async {
    await t.pumpWidget(_host(_group(5)));
    expect(find.byKey(const Key('paidToAccountsPager')), findsNothing);
    expect(find.byKey(const Key('paidToAccountsPageLabel')), findsNothing);
    expect(find.byKey(const Key('paidToAccountsDot-0')), findsNothing);
    expect(find.byKey(const Key('paidToAccount-4')), findsOneWidget);
    await t.pumpWidget(_host(_group(2)));
    expect(find.byKey(const Key('paidToAccount-1')), findsOneWidget);
  });

  testWidgets('large text 1.3 on a narrow phone: no overflow', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: SingleChildScrollView(child: PaidToAccountsBlock(palette: AppPalette.dark, recipient: _group(25))),
            ),
          ),
        ),
      ),
    );
    expect(tester0(t), isNull);
  });
}

Object? tester0(WidgetTester t) => t.takeException();
