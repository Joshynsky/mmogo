/// §AUTOREAD.CATEGORIZE_DETAILS — the read-only parts of the Categorize sheet: the header with Close,
/// the "Check this one" flag and the details block (split from categorize_sheet.dart, 0.2.2; no behaviour change).
library;

import 'package:flutter/material.dart';

import '../../domain/format/money.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/theme/app_colors.dart';
import '../model/waiting_item.dart';
import 'categorize_copy.dart';
import 'notifications_autoread_copy.dart';

class CategorizeHeader extends StatelessWidget {
  const CategorizeHeader({super.key, required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              kActionCategorize,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('categorizeClose'),
          tooltip: kCategorizeClose,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(Icons.close, color: palette.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
  }
}

class CategorizeDetails extends StatelessWidget {
  const CategorizeDetails({super.key, required this.item, required this.palette});
  final WaitingItem item;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
  final p = item.parsed;
  final flagged = item.sameCodeDifferentDetails;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (flagged)
      Container(
        key: const Key('categorizeFlag'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: palette.tintInk,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: kCategorizeCheckThis,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: ' $kFlaggedLine'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: palette.tintInk,
                ),
              ),
            ),
          ],
        ),
      ),
    if (p != null)
      Container(
        key: const Key('categorizeDetails'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            categorizeDetailRow(
              palette,
              kCategorizeLabelType,
              categorizeTypeLabel(p.sourceType),
            ),
            categorizeDetailRow(
              palette,
              kCategorizeLabelAmount,
              formatKsh(p.amountCents),
            ),
            categorizeDetailRow(
              palette,
              kCategorizeLabelPaidTo,
              p.counterpartyLabel ?? '—',
            ),
            categorizeDetailRow(
              palette,
              kCategorizeLabelDate,
              categorizeDateTime(
                DateTime.fromMillisecondsSinceEpoch(p.transactionOccurredAt),
              ),
            ),
            categorizeDetailRow(
              palette,
              kCategorizeLabelCost,
              formatKsh(p.transactionCostCents),
            ),
          ],
        ),
      ),
  ]);
  }
}

Widget categorizeDetailRow(AppPalette palette, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: palette.mutedInk),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String categorizeTypeLabel(SmsSourceType t) => switch (t) {
  SmsSourceType.sendMoney => 'Send Money',
  SmsSourceType.payBill => 'Paybill',
  SmsSourceType.buyGoods => 'Buy Goods',
  SmsSourceType.pochi => 'Pochi La Biashara',
  SmsSourceType.agentWithdrawal => 'Withdrawal',
  SmsSourceType.airtime => 'Airtime',
};

/// The mock's date text: `18-10-2026, 08:30`.
String categorizeDateTime(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}-${p(d.month)}-${d.year}, ${p(d.hour)}:${p(d.minute)}';
}

/// A small bold section label ("Category", "Suggested", ...).
Widget categorizeLabel(AppPalette palette, String text) => Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.ink),
    );
