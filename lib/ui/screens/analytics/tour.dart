import 'package:flutter/widgets.dart';

import '../../widgets/coach_tour.dart';

/// Analytics' coach-tour page id (the seen flag is `tour_seen_analytics`).
const analyticsTourId = 'analytics';

/// The Analytics tour: period pill, chart, breakdown chips, then (only when
/// there is a row to point at) the swipe actions on the first row.
List<CoachStep> analyticsTourSteps({
  required GlobalKey granKey,
  required GlobalKey chartKey,
  required GlobalKey breakdownKey,
  required GlobalKey? firstRowKey,
}) {
  return [
    CoachStep(target: granKey, text: 'Change the period. Custom lets you pick any range.'),
    CoachStep(
      target: chartKey,
      text: 'Tap a bar to zoom in. Swipe or use the arrows for other periods.',
      onEnter: () => scrollIntoView(chartKey),
    ),
    CoachStep(
      target: breakdownKey,
      text: 'Tap a type or category to filter the list. Tap x to clear.',
      onEnter: () => scrollIntoView(breakdownKey),
    ),
    if (firstRowKey != null)
      CoachStep(
        target: firstRowKey,
        text: 'Swipe right to edit, left to delete. Undo appears for a few seconds.',
        onEnter: () => scrollIntoView(firstRowKey),
      ),
  ];
}
