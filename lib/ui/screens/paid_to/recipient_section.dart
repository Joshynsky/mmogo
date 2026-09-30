import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/tabular.dart';
import 'recipient_row.dart';

/// §PAIDTO.SECTION — one type's section: the header (name, total, counts, "See all N ›") and the ranked recipient card.
class PaidToSectionHeader extends StatelessWidget {
  const PaidToSectionHeader({
    super.key,
    required this.palette,
    required this.section,
    required this.seeAll,
    required this.onSeeAll,
  });

  final AppPalette palette;
  final PaidToSection section;

  /// Whether to show the "See all N ›" link (overview with more than 3).
  final bool seeAll;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final n = s.recipients.length;
    final subStyle = TextStyle(fontSize: 11.5, height: 1.5, color: palette.mutedInk);
    return Padding(
      key: Key('paidToSection-${s.type}'),
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  sourceTypeName(s.type).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: palette.mutedInk,
                  ),
                ),
              ),
              Text(
                formatKsh(s.totalCents),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                  color: palette.softInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$n ${paidToNoun(s.type, n)} · ${s.payments} payment${s.payments == 1 ? '' : 's'}'
                ' · fees ${kshTrim(s.feeCents)}',
                key: Key('paidToSectionSub-${s.type}'),
                style: subStyle,
              ),
              if (seeAll) ...[
                Text(' · ', style: subStyle),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    key: Key('paidToSeeAll-${s.type}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onSeeAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'See all $n ›',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: palette.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The card of ranked [PaidToRecipientRow]s under a section header.
class PaidToListCard extends StatelessWidget {
  const PaidToListCard({
    super.key,
    required this.palette,
    required this.shown,
    required this.ranked,
    required this.sort,
    required this.today,
    required this.onOpen,
  });

  final AppPalette palette;
  final List<PaidToRecipient> shown;
  final bool ranked;
  final PaidToSort sort;
  final DateTime today;
  final void Function(PaidToRecipient recipient) onOpen;

  @override
  Widget build(BuildContext context) {
    final metric = switch (sort) {
      PaidToSort.amount => (PaidToRecipient g) => g.totalCents,
      PaidToSort.timesPaid => (PaidToRecipient g) => g.count,
      PaidToSort.recent => null,
    };
    final max = metric == null ? 1 : shown.map(metric).fold<int>(1, math.max);
    return AppCard(
      palette: palette,
      clip: true,
      child: Column(
        children: [
          for (final (i, g) in shown.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: palette.line),
            PaidToRecipientRow(
              key: ValueKey('paidToRow-${g.key}'),
              palette: palette,
              recipient: g,
              rank: ranked ? i + 1 : null,
              share: metric == null ? null : metric(g) / max,
              sort: sort,
              today: today,
              onTap: () => onOpen(g),
            ),
          ],
        ],
      ),
    );
  }
}
