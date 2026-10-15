import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_counts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/period_pill.dart';
import '../../widgets/tabular.dart';

/// §PAIDTO.HERO — the "Paid out" card (mock `renderHero`): period pill, total, the Transaction
/// cost line, "to N recipients", "N payments", "+ M agents (cash out, not counted)" and the
/// separate "Transaction cost of withdrawals" line. Always the whole period, never narrowed by
/// the search, the category or a payment-type pill; with the W pill open it reads "Withdrawn:
/// from N agents, N withdrawals" (numbers from `paidToHero`).
class PaidToHeroCard extends StatelessWidget {
  const PaidToHeroCard({
    super.key,
    required this.palette,
    required this.hero,
    required this.shown,
    required this.first,
    required this.today,
    required this.granKey,
    required this.valueKey,
    required this.onGranularity,
    required this.onValue,
  });

  final AppPalette palette;
  final PaidToHero hero;

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
    final w = hero.agentView;
    final total = hero.totalCents;
    final recipients = hero.recipients;
    final count = hero.payments;
    final costStyle = TextStyle(fontSize: 12.5, color: palette.softInk, fontFeatures: tabularFigures);
    final costBold = TextStyle(fontWeight: FontWeight.w700, color: palette.ink, fontFeatures: tabularFigures);
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
                    w ? 'Withdrawn' : 'Paid out',
                    key: const Key('paidToHeroLabel'),
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
          const SizedBox(height: 3),
          Text.rich(
            key: const Key('paidToCost'),
            TextSpan(
              style: costStyle,
              children: [
                const TextSpan(text: 'Transaction cost '),
                TextSpan(text: formatKsh(hero.costCents), style: costBold),
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
                    TextSpan(text: w ? 'from ' : 'to '),
                    TextSpan(text: '$recipients', style: factBold),
                    TextSpan(
                      text: w
                          ? ' ${paidToNoun(paidToWithdrawal, recipients)}'
                          : ' recipient${recipients == 1 ? '' : 's'}',
                    ),
                  ],
                ),
              ),
              Text.rich(
                key: const Key('paidToFactPayments'),
                TextSpan(
                  style: factStyle,
                  children: [
                    TextSpan(text: '$count', style: factBold),
                    TextSpan(text: ' ${w ? paidToPayWord(paidToWithdrawal, count) : paidToPayWord('', count)}'),
                  ],
                ),
              ),
              if (!w && hero.agents > 0)
                Text.rich(
                  key: const Key('paidToFactAgents'),
                  TextSpan(
                    style: factStyle,
                    children: [
                      const TextSpan(text: '+ '),
                      TextSpan(text: '${hero.agents}', style: factBold),
                      TextSpan(text: ' ${paidToNoun(paidToWithdrawal, hero.agents)} (cash out, not counted)'),
                    ],
                  ),
                ),
            ],
          ),
          if (!w && hero.withdrawalCostCents > 0) ...[
            const SizedBox(height: 3),
            Text.rich(
              key: const Key('paidToWithdrawalCost'),
              TextSpan(
                style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.mutedInk, fontFeatures: tabularFigures),
                children: [
                  const TextSpan(text: 'Transaction cost of withdrawals '),
                  TextSpan(
                    text: formatKsh(hero.withdrawalCostCents),
                    style: TextStyle(fontWeight: FontWeight.w700, color: palette.softInk),
                  ),
                  const TextSpan(text: ' (not in the figures above)'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
