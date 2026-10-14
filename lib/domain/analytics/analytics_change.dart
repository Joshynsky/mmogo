/// §DOMAIN.ANALYTICS_CHANGE — what Analytics' change pill says (0.1.2 S6b,
/// P-Analytics-02). Built on the one shared Week / Month rule in
/// `domain/period_change.dart` (also used by Home) and its Year twin.
///
/// Pure Dart. Tested in `test/domain/analytics/analytics_change_test.dart`.
library;

import '../home/home_diff.dart';
import '../period_change.dart';
import 'analytics_period.dart';

enum ChangeLook {
  /// The progress cue ("3/7"): muted flat text standing in for the pill.
  cue,

  /// Muted flat text: "—", "no spending", "nothing before to compare".
  flat,

  /// Red up arrow.
  up,

  /// Green down arrow.
  down,
}

class ChangeDisplay {
  const ChangeDisplay(this.look, this.text, {this.label, this.tooltip});

  final ChangeLook look;
  final String text;

  /// Screen-reader text (the cue only).
  final String? label;

  /// Tooltip / title text (the cue only).
  final String? tooltip;
}

/// The pill for one period, or `null` when there is nothing to compare with
/// (All time). [priorCents] is the total of the equally long period before:
/// for Week and Month the WHOLE previous calendar week / month, for Year the
/// whole previous year. [vs] is the caption ("vs last week").
ChangeDisplay? analyticsChange({
  required AnalyticsGranularity granularity,
  required DayRange range,
  required DateTime today,
  required int totalCents,
  required int? priorCents,
  required String vs,
}) {
  if (priorCents == null || granularity == AnalyticsGranularity.all) return null;
  final weekOrMonth = granularity == AnalyticsGranularity.week || granularity == AnalyticsGranularity.month;
  if (weekOrMonth) {
    final p = periodProgress(
      granularity == AnalyticsGranularity.week ? ProgressKind.week : ProgressKind.month,
      range.start,
      today,
    );
    if (p.hide) return ChangeDisplay(ChangeLook.cue, p.cue, label: p.analyticsLabel, tooltip: p.analyticsTooltip);
  } else if (granularity == AnalyticsGranularity.year) {
    final y = yearProgress(range.start.year, today);
    if (y.hide) return ChangeDisplay(ChangeLook.cue, y.cue, label: y.label, tooltip: y.tooltip);
  }
  final diff = HomeDiff.compute(thisTotalCents: totalCents, priorTotalCents: priorCents);
  final caption = vs.isEmpty ? '' : ' $vs';
  return switch (diff.kind) {
    HomeDiffKind.noPriorNoSpend => const ChangeDisplay(ChangeLook.flat, 'no spending'),
    HomeDiffKind.noPriorHasSpend => const ChangeDisplay(ChangeLook.flat, 'nothing before to compare'),
    // Equal totals: Week and Month say "—" (never "= 0%"); the other
    // periods keep 0.1.1's "▲ 0%".
    HomeDiffKind.flat =>
      weekOrMonth ? const ChangeDisplay(ChangeLook.flat, '—') : ChangeDisplay(ChangeLook.up, '▲ 0%$caption'),
    HomeDiffKind.up => ChangeDisplay(ChangeLook.up, '▲ ${diff.percent}%$caption'),
    HomeDiffKind.down => ChangeDisplay(ChangeLook.down, '▼ ${diff.percent}%$caption'),
  };
}
