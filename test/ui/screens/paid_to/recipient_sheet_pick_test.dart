// 0.2.1 #4 (MK-12): choose one account in the recipient sheet; Showing chip; See in Analytics; chart windows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/paid_to/paid_to_sheet.dart';
import 'package:mmogo/ui/screens/paid_to/not_recorded_explainer.dart';
import 'package:mmogo/ui/screens/paid_to/recipient_sheet.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

PaidToPayment _p(String account, DateTime at, int ksh) => PaidToPayment(
  sourceType: 'PAYBILL',
  amountCents: ksh * 100,
  feeCents: 0,
  occurredAt: at,
  classificationName: account == 'A1' ? 'Rent' : 'Fees',
  label: 'DIRECT PAY 04',
  account: account,
);

PaidToRecipient _group(List<PaidToPayment> pays) {
  PaidToGrouping.paybillByName = true;
  final r = groupPaidTo(pays).single;
  PaidToGrouping.paybillByName = false;
  return r;
}

final _range = DayRange(DateTime(2025, 1, 1), DateTime(2026, 10, 31));

/// Opens the sheet over a button; [result] receives what the sheet hands back.
Future<void> _open(
  WidgetTester t,
  PaidToRecipient r, {
  bool allTime = true,
  void Function(PaidToSheetExit?)? result,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 1400);
  addTearDown(t.view.reset);
  PaidToSheetData dataFor(int? a) => paidToSheetData(r, range: _range, month: false, allTime: allTime, account: a);
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () async {
              final out = await showPaidToRecipientSheet(
                c,
                palette: AppPalette.light,
                recipient: r,
                data: dataFor(null),
                dataFor: dataFor,
                periodWords: 'since Sep 2025',
              );
              result?.call(out);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  tearDown(() => PaidToGrouping.paybillByName = false);

  final pays = [
    _p('A1', DateTime(2025, 9, 3), 500),
    _p('A1', DateTime(2026, 10, 25), 200),
    _p('A2', DateTime(2026, 1, 9), 100),
  ];

  testWidgets('nothing chosen on open: chip says all accounts, See in Analytics is off with its reason', (t) async {
    await _open(t, _group(pays));
    expect(
      find.descendant(of: find.byKey(const Key('paidToShowingChip')), matching: find.textContaining('all accounts')),
      findsOneWidget,
    );
    expect(t.widget<FilledButton>(find.byKey(const Key('paidToSheetAnalytics'))).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.byKey(const Key('paidToAllAccounts'))).onPressed, isNull);
    expect(find.text('Pick one account to open it in Analytics'), findsOneWidget);
    expect(find.byKey(const Key('paidToAccountSelected-0')), findsNothing);
  });

  testWidgets('tap an account: Selected, chip, figures follow; tap again or All accounts goes back', (t) async {
    await _open(t, _group(pays));
    expect(find.byKey(const Key('paidToSheetCat-Rent')), findsOneWidget);
    await _tapKey(t, 'paidToAccountTap-1');
    expect(find.byKey(const Key('paidToAccountSelected-1')), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Opens account A2 in Analytics'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('paidToSheetAnalytics'))).onPressed, isNotNull);
    expect(find.byKey(const Key('paidToSheetCat-Fees')), findsOneWidget);
    expect(find.byKey(const Key('paidToSheetCat-Rent')), findsNothing);
    // the ACCOUNTS list and Total stay combined
    expect(find.text('2 accounts · 3 payments'), findsOneWidget);
    await _tapKey(t, 'paidToAllAccounts');
    expect(find.byKey(const Key('paidToAccountSelected-1')), findsNothing);
    expect(find.byKey(const Key('paidToSheetCat-Rent')), findsOneWidget);
    await _tapKey(t, 'paidToAccountTap-0');
    expect(find.byKey(const Key('paidToAccountSelected-0')), findsOneWidget);
    await _tapKey(t, 'paidToAccountTap-0');
    expect(find.byKey(const Key('paidToAccountSelected-0')), findsNothing);
  });

  testWidgets('See in Analytics hands back the chosen account', (t) async {
    PaidToSheetExit? got;
    await _open(t, _group(pays), result: (o) => got = o);
    await _tapKey(t, 'paidToAccountTap-1');
    await _tapKey(t, 'paidToSheetAnalytics');
    expect(got, isNotNull);
    expect(got!.account, 'A2');
  });

  testWidgets('All time over 4 months: a swipeable chart, latest window first, dots and range line', (t) async {
    await _open(t, _group(pays));
    expect(find.byKey(const Key('paidToChartPages')), findsOneWidget);
    expect(find.byKey(const Key('paidToChartDot-3')), findsOneWidget);
    expect(find.byKey(const Key('paidToChartDot-4')), findsNothing);
    expect(find.textContaining('Jul to Oct 2026'), findsOneWidget);
    await t.drag(find.byKey(const Key('paidToChartPages')), const Offset(300, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Mar to Jun 2026'), findsOneWidget);
    await t.tap(find.byKey(const Key('paidToChartDot-0')));
    await t.pumpAndSettle();
    expect(find.textContaining('Sep to Oct 2025'), findsOneWidget);
  });

  testWidgets('a name with one account is as built: no chip, See in Analytics on', (t) async {
    PaidToSheetExit? got;
    await _open(
      t,
      _group([_p('A1', DateTime(2026, 10, 25), 200), _p('A1', DateTime(2026, 9, 25), 200)]),
      allTime: false,
      result: (o) => got = o,
    );
    expect(find.byKey(const Key('paidToShowingChip')), findsNothing);
    expect(find.byKey(const Key('paidToAnalyticsWhy')), findsNothing);
    await _tapKey(t, 'paidToSheetAnalytics');
    expect(got, isNotNull);
    expect(got!.account, isNull);
  });

  testWidgets('the Receiver not saved explainer names the switch and offers Settings', (t) async {
    bool? open;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () async => open = await showPaidToNotRecordedExplainer(c, palette: AppPalette.light),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    expect(find.textContaining('Record receiver details'), findsOneWidget);
    await t.tap(find.byKey(const Key('paidToNotRecordedSettings')));
    await t.pumpAndSettle();
    expect(open, isTrue);
  });
}
