// 0.2.1: Home recents: "Cash — Rent · from withdrawal" and the withdrawal's "→ Rent".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/home/recent_transaction.dart';
import 'package:mmogo/ui/screens/home/recent_list.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

void main() {
  testWidgets('the entry and the withdrawal read as designed', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final at = DateTime(2026, 11, 17, 14, 5);
    final rows = [
      RecentTransaction(
        id: 2,
        displayCode: 'CASH-20261117-1405',
        sourceType: 'CASH',
        amountCents: 500000,
        counterpartyLabel: null,
        classificationName: 'Rent',
        occurredAt: at,
        parentTransactionId: 1,
      ),
      RecentTransaction(
        id: 1,
        displayCode: 'WDR0000001',
        sourceType: 'AGENT_WITHDRAWAL',
        amountCents: 500000,
        counterpartyLabel: 'Test Agent',
        classificationName: 'Withdrawal',
        occurredAt: at,
        feeCents: 3300,
        agentNumber: '123456',
        linkedCategoryNames: const ['Rent'],
      ),
    ];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [HomeRecentSliver(palette: AppPalette.light, recent: rows, onTap: (_) {})]),
      ),
    ));
    expect(find.text('Cash — Rent'), findsOneWidget);
    expect(find.textContaining('from withdrawal'), findsOneWidget);
    expect(find.textContaining('→ Rent'), findsOneWidget);
    // Both rows keep the one fixed height.
    expect(t.getSize(find.byKey(const Key('homeRecentRow-1'))).height, t.getSize(find.byKey(const Key('homeRecentRow-2'))).height);
  });
}
