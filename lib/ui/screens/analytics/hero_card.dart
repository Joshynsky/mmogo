import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/home/home_diff.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/period_pill.dart';
import '../../widgets/tabular.dart';
import 'analytics_view.dart';
import 'parts.dart';

/// §ANALYTICS.HERO — the total card: Spent label, period pill, calendar
/// button, Ksh total, change pill and the count/avg/fees facts. Everything
/// shown is derived from [view]; the shell owns the pill keys and menus.
class AnalyticsHeroCard extends StatelessWidget {
  const AnalyticsHeroCard({
    super.key,
    required this.palette,
    required this.view,
    required this.words,
    required this.granKey,
    required this.valueKey,
    required this.onGranularity,
    required this.onValue,
    required this.onCustom,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final PeriodWords words;
  final GlobalKey granKey;
  final GlobalKey valueKey;
  final VoidCallback onGranularity;
  final VoidCallback onValue;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final total = v.totalCents;
    final count = v.inc.length;
    final fees = v.inc.fold<int>(0, (s, r) => s + (r.transactionCostCents ?? 0));
    final elapsed = v.period.elapsedDays(today: v.today, first: v.first);

    Widget? pill;
    if (v.party) {
      pill = _ChangePill.flat(palette, '$count payment${count == 1 ? '' : 's'}');
    } else if (v.priorCents != null) {
      final diff = HomeDiff.compute(thisTotalCents: total, priorTotalCents: v.priorCents!);
      pill = switch (diff.kind) {
        HomeDiffKind.noPriorNoSpend => _ChangePill.flat(palette, 'no spending'),
        HomeDiffKind.noPriorHasSpend => _ChangePill.flat(palette, 'nothing before to compare'),
        HomeDiffKind.up => _ChangePill(
          text: '▲ ${diff.percent}% ${words.vs}',
          color: palette.diffUp,
          background: palette.diffUp.withValues(alpha: 0.12),
        ),
        HomeDiffKind.down => _ChangePill(
          text: '▼ ${diff.percent}% ${words.vs}',
          color: palette.diffDown,
          background: palette.diffDown.withValues(alpha: 0.12),
        ),
      };
    }

    final factStyle = TextStyle(fontSize: 12, color: palette.mutedInk);
    final factBold = TextStyle(fontWeight: FontWeight.w700, color: palette.ink, fontFeatures: tabularFigures);
    Widget fact(Key key, List<InlineSpan> spans) => Text.rich(
      TextSpan(style: factStyle, children: spans),
      key: key,
    );

    final period = v.period;
    final isCustom = period.granularity == AnalyticsGranularity.custom;

    return AppCard(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, rc) {
              final rowWidth = rc.maxWidth;
              return Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: v.party ? 'Paid to them' : words.spent,
                      child: Text(
                        v.party ? 'Paid to them' : 'Spent',
                        key: const Key('analyticsSpentLabel'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.softInk),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Never wider than the row minus the calendar button and room
                  // for "Spent"; at very large text it scales down instead of
                  // overflowing.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.max(0.0, rowWidth - 30 - 12 - 40)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: PeriodPill(
                        palette: palette,
                        granKey: granKey,
                        valueKey: valueKey,
                        granularity: period.granularityLabel,
                        value: words.value,
                        onGranularity: onGranularity,
                        onValue: onValue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnalyticsRoundButton(
                    key: const Key('analyticsCalendar'),
                    size: 30,
                    icon: Icons.calendar_today_outlined,
                    iconSize: 15,
                    tooltip: 'Custom dates',
                    background: isCustom ? palette.primary : palette.track,
                    foreground: isCustom ? palette.onPrimary : palette.ink,
                    onTap: onCustom,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth),
                  child: FittedBox(
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
                          key: const Key('analyticsTotal'),
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
                ),
                ?pill,
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              fact(const Key('analyticsFactCount'), [
                TextSpan(text: '$count', style: factBold),
                TextSpan(text: ' transaction${count == 1 ? '' : 's'}'),
              ]),
              if (period.granularity != AnalyticsGranularity.day && count > 0 && elapsed > 1)
                fact(const Key('analyticsFactAvg'), [
                  const TextSpan(text: 'avg '),
                  TextSpan(text: kshTrim(((total / elapsed) / 100).round() * 100), style: factBold),
                  const TextSpan(text: '/day'),
                ]),
              fact(const Key('analyticsFactFees'), [
                const TextSpan(text: 'fees '),
                TextSpan(text: kshTrim(fees), style: factBold),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.text, required this.color, required this.background});

  factory _ChangePill.flat(AppPalette palette, String text) =>
      _ChangePill(text: text, color: palette.mutedInk, background: palette.track);

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('analyticsChange'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: const BorderRadius.all(Radius.circular(999))),
      child: Text(
        text,
        softWrap: false,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
