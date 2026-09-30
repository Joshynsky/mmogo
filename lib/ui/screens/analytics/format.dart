import '../../../domain/format/source_types.dart';

/// §ANALYTICS.FORMAT — type order, time-of-day and durations shared by the Analytics sections.
/// The four types in the fixed chart order (colours c1–c4, T20).
const analyticsTypeOrder = sourceTypeOrder;

String analyticsHhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// How long a row stays lit after the Home hand-off, an edit or an Undo.
const analyticsHighlightDuration = Duration(milliseconds: 1800);

/// How long the "moved to Recently Deleted" toast (with Undo) stays up.
const analyticsToastDuration = Duration(seconds: 5);
