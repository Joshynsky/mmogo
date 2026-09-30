import 'dart:async';

import 'package:mpesa_tracker/ui/widgets/coach_tour.dart';

/// Runs for every test file: page tests should not have a first-run coach
/// tour covering the page. The tour's own tests set `autoStartDisabled` back
/// to false in their setUp.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CoachTour.autoStartDisabled = true;
  await testMain();
}
