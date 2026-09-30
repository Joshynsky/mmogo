import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/period_pill.dart';
import '../../widgets/tabular.dart';

/// §PAIDTO.HERO — the "Paid out" card: period pill, total, recipient and payment counts.
/// Always the whole period, never narrowed by the type pill or the filter.
class PaidToHeroCard extends StatelessWidget {
  const PaidToHeroCard({
    super.key,
    required this.palette,
    required this.payments,
    required this.shown,
    required this.first,
    required this.today,
    required this.granKey,
    required this.valueKey,
    required this.onGranularity,
    required this.onValue,
  });

  final AppPalette palette;
  final List<PaidToPayment> payments;

  /// The period the payments belong to.
  final AnalyticsPeriod shown;
  final DateTime? first;
  final DateTime today;
  final GlobalKey granKey;
  final GlobalKey valueKey;
  final VoidCallback onGranularity;

  /// `null` on All time (the value pill is inert).
  final VoidCallback? onValue;

  @override
  Widget build(BuildContext context) {
    final words = shown.words(today: today, first: first);
    final total = payments.fold<int>(0, (s, p) => s + p.amountCents);
    final recipients = countPaidToRecipients(payments);
    final count = payments.length;
    final factStyle = TextStyle(fontSize: 12, color: palette.mutedInk);
    final factBold = TextStyle(fontWeight: FontWeight.w700, color: palette.ink, fontFeatures: tabularFigures);
    return AppCard(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, rc) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Paid out',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.softInk),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: math.max(0.0, rc.maxWidth - 70)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: PeriodPill(
                      palette: palette,
                      granKey: granKey,
                      valueKey: valueKey,
                      granularityTapKey: const Key('paidToGranularity'),
                      valueTapKey: const Key('paidToPeriodValue'),
                      granularity: shown.granularityLabel,
                      value: words.value,
                      onGranularity: onGranularity,
                      onValue: onValue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Ksh',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.softInk),
                ),
                const SizedBox(width: 4),
                Text(
                  formatKsh(total).substring(4),
                  key: const Key('paidToTotal'),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.05,
                    fontFeatures: tabularFigures,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text.rich(
                key: const Key('paidToFactRecipients'),
                TextSpan(
                  style: factStyle,
                  children: [
                    const TextSpan(text: 'to '),
                    TextSpan(text: '$recipients', style: factBold),
                    TextSpan(text: ' recipient${recipients == 1 ? '' : 's'}'),
                  ],
                ),
              ),
              Text.rich(
                key: const Key('paidToFactPayments'),
                TextSpan(
                  style: factStyle,
                  children: [
                    TextSpan(text: '$count', style: factBold),
                    TextSpan(text: ' payment${count == 1 ? '' : 's'}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
