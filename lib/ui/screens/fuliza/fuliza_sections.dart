import 'package:flutter/material.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/fuliza/fuliza_page_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/tabular.dart';
import '../analytics/format.dart';

/// §FULIZA.SECTIONS — 0.2.0 S9: the stateless blocks of the Fuliza page (mock `plugins/fuliza.js`
/// `render`): summary card, a titled section, History by day, Related transactions.
/// WORDING-DRAFT: every label below is a plain label for the PM to review ("Owing now", "Nothing owed",
/// "Owing unknown", "Taken", "Repaid", "Fuliza cost", "(estimated)", "Carried in from before the data",
/// "Borrowed", "Repaid in full", "Part repayment", "On Fuliza", "Part on Fuliza", the notes).

String _ksh(int c) => formatKsh(c);

TextStyle _num(AppPalette p, double size, {FontWeight w = FontWeight.w800, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: w, fontFeatures: tabularFigures, color: color ?? p.ink);

/// "Owing now Ksh X" with Taken / Repaid / Fuliza cost, the estimated note, the unknown state.
class FulizaSummaryCard extends StatelessWidget {
  const FulizaSummaryCard({super.key, required this.palette, required this.data});

  final AppPalette palette;
  final FulizaPageData data;

  String _whole(int c) => kshTrim((c / 100).round() * 100);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final d = data;
    final label = d.owingUnknown ? 'Owing unknown' : (d.nothingOwed ? 'Nothing owed' : 'Owing now');
    final amount = d.owingUnknown ? '—' : '${d.owingIsEstimate ? 'about ' : ''}${_ksh(d.owingCents!)}';
    Widget stat(String l, String v, {String? note}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: TextStyle(fontSize: 11.5, color: p.mutedInk)),
          Text(v, style: _num(p, 14)),
          if (note != null) Text(note, style: TextStyle(fontSize: 11, color: p.mutedInk)),
        ],
      ),
    );
    return AppCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            key: const Key('fulizaOwingLabel'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.softInk),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(amount, key: const Key('fulizaOwingAmount'), style: _num(p, 27)),
          ),
          if (d.owingUnknown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The first Fuliza message we saw was a part repayment, so the balance is not known yet. It is worked out again at the next borrowing.',
                key: const Key('fulizaUnknownNote'),
                style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk),
              ),
            )
          else if (d.owingIsEstimate)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'About, because it was worked out after a part repayment (estimated).',
                key: const Key('fulizaEstimateNote'),
                style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk),
              ),
            ),
          if (d.nothingOwed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Paid back in full on ${fmtDayMonth(d.to)}.',
                style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk),
              ),
            ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: 'Summary, ${fmtDayMonth(d.from)} to ${fmtDayMonth(d.to)}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stat('Taken', _whole(d.takenCents)),
                const SizedBox(width: 8),
                stat('Repaid', _whole(d.repaidCents)),
                const SizedBox(width: 8),
                stat('Fuliza cost', _whole(d.costCents), note: '(estimated)'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${fmtDayMonth(d.from)} to ${fmtDayMonth(d.to)}: you took Fuliza ${d.drawCount} ${d.drawCount == 1 ? 'time' : 'times'}. '
            'Fuliza cost = access fees + daily fees. About Ksh ${d.costPer100} in every Ksh 100 you took went on fees. '
            'Borrowed amounts and repayments are not counted as spending.',
            key: const Key('fulizaSummaryText'),
            style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk),
          ),
        ],
      ),
    );
  }
}

/// A titled block on its own card, with an optional muted note under it.
class FulizaSection extends StatelessWidget {
  const FulizaSection({super.key, required this.palette, required this.title, required this.children, this.note});

  final AppPalette palette;
  final String title;
  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AppCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.mutedInk),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(note!, style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk)),
            ),
        ],
      ),
    );
  }
}

/// One label / value line.
class FulizaFigureLine extends StatelessWidget {
  const FulizaFigureLine({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final AppPalette palette;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: palette.softInk,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(value, style: _num(palette, 12.5, w: strong ? FontWeight.w800 : FontWeight.w700)),
      ],
    ),
  );
}

/// History by day, newest first. A borrowing whose spend is known can be opened ([onOpenSpend]); the entry
/// of [focusCode] is lit and carries [focusKey] so the screen can scroll to it.
class FulizaHistory extends StatelessWidget {
  const FulizaHistory({
    super.key,
    required this.palette,
    required this.data,
    required this.spends,
    required this.onOpenSpend,
    this.focusCode,
    this.focusKey,
  });

  final AppPalette palette;
  final FulizaPageData data;
  final Map<String, AnalyticsTransactionRow> spends;
  final void Function(AnalyticsTransactionRow tx) onOpenSpend;
  final String? focusCode;
  final GlobalKey? focusKey;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final children = <Widget>[];
    for (final day in data.days) {
      final total = day.repaidCents > 0 ? 'Repaid ${_ksh(day.repaidCents)}' : 'Borrowed ${_ksh(day.borrowedCents)}';
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${fmtDayMonth(day.day)} · ${weekdayShort(day.day)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.softInk),
                ),
              ),
              Text(
                total,
                style: _num(p, 12, w: FontWeight.w700, color: p.softInk),
              ),
            ],
          ),
        ),
      );
      for (final e in day.entries) {
        final spend = e.isDraw ? spends[e.event.code] : null;
        final lit = focusCode != null && e.isDraw && e.event.code == focusCode;
        children.add(
          _Entry(key: lit ? focusKey : null, palette: p, entry: e, spend: spend, lit: lit, onOpenSpend: onOpenSpend),
        );
      }
    }
    if (data.carriedInCents != null) {
      children.add(
        Container(
          key: const Key('fulizaCarriedIn'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Mark(palette: p, text: '•'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carried in from before the data',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    Text(
                      'Before ${fmtDayMonth(data.from)} · about ${kshTrim((data.carriedInCents! / 100).round() * 100)} was already owed',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_ksh(data.carriedInCents!), style: _num(p, 13)),
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.palette, required this.text});

  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: palette.track, borderRadius: const BorderRadius.all(Radius.circular(9))),
    child: ExcludeSemantics(
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.softInk),
      ),
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.palette,
    required this.entry,
    required this.spend,
    required this.lit,
    required this.onOpenSpend,
  });

  final AppPalette palette;
  final FulizaHistoryEntry entry;
  final AnalyticsTransactionRow? spend;
  final bool lit;
  final void Function(AnalyticsTransactionRow tx) onOpenSpend;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final e = entry.event;
    final title = entry.isDraw ? 'Borrowed' : (entry.isFullRepayment ? 'Repaid in full' : 'Part repayment');
    final bits = <String>[analyticsHhmm(e.at)];
    if (entry.isDraw) {
      if (spend != null) bits.add('for ${spend!.displayName}');
      bits.add('access fee ${_ksh(e.feeCents)}');
      if (entry.dailyFeeSeenCents > 0) bits.add('daily fee seen ${kshTrim(entry.dailyFeeSeenCents)} (estimated)');
    }
    if (entry.owingAfterCents != null) bits.add('owing ${_ksh(entry.owingAfterCents!)}');
    final amount = '${entry.isDraw ? '' : '− '}${_ksh(e.amountCents)}';
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: lit ? p.highlight : null,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Mark(palette: p, text: entry.isDraw ? 'F' : '✓'),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                ),
                Text(bits.join(' · '), style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(amount, style: _num(p, 13)),
        ],
      ),
    );
    return Semantics(
      key: Key('fulizaEntry-${e.code}-${entry.isDraw ? 'draw' : 'repay'}'),
      container: true,
      selected: lit,
      button: spend != null,
      label: '$title, $amount, ${bits.join(', ')}',
      excludeSemantics: true,
      child: spend == null
          ? body
          : InkWell(
              onTap: () => onOpenSpend(spend!),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: body,
            ),
    );
  }
}

/// Related transactions: the spends a borrowing paid for. The row body opens the edit sheet; the arrow
/// ([onShow]) opens THAT borrowing inside the Fuliza page (History, lit) and Back returns here.
class FulizaRelatedRow extends StatelessWidget {
  const FulizaRelatedRow({
    super.key,
    required this.palette,
    required this.tx,
    required this.drawCents,
    required this.onOpen,
    required this.onShow,
  });

  final AppPalette palette;
  final AnalyticsTransactionRow tx;
  final int drawCents;
  final VoidCallback onOpen;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final full = drawCents >= tx.amountCents;
    final d = tx.occurredAt;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: '${tx.displayName}, ${_ksh(tx.amountCents)}, ${full ? 'on Fuliza' : 'part on Fuliza'}. Open',
            excludeSemantics: true,
            child: InkWell(
              key: Key('fulizaRelated-${tx.displayCode}'),
              onTap: onOpen,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.displayName,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              _Chip(palette: p, text: full ? 'On Fuliza' : 'Part on Fuliza', part: !full),
                              Text(
                                '${sourceTypeName(tx.sourceType)} · ${fmtDayMonth(d)}, ${analyticsHhmm(d)}',
                                style: TextStyle(fontSize: 11.5, color: p.mutedInk),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_ksh(tx.amountCents), style: _num(p, 13)),
                        if (!full)
                          Text('${kshTrim(drawCents)} on Fuliza', style: TextStyle(fontSize: 11, color: p.mutedInk)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Show ${tx.displayName} in the Fuliza history',
          excludeSemantics: true,
          child: InkWell(
            key: Key('fulizaShow-${tx.displayCode}'),
            onTap: onShow,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.chevron_right_rounded, size: 22, color: p.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.palette, required this.text, required this.part});

  final AppPalette palette;
  final String text;
  final bool part;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: palette.primary.withValues(alpha: part ? 0.10 : 0.16),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.softInk),
    ),
  );
}
