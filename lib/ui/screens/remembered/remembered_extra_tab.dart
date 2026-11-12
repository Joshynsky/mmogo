import 'package:flutter/widgets.dart';

/// §SCREEN.REMEMBERED.EXTRA_TAB: what the Remembered page needs from an
/// optional second tab. Plain Dart and Flutter; this file imports nothing from
/// the auto-read folder, so the standard build's page stays what it is. The
/// page shows tabs only when it is given one of these.
abstract class RememberedExtraTab {
  /// Fires when [tabLabel] may have changed (for example a switch flipped).
  Listenable get listenable;

  /// The page title when the second tab is present.
  String get pageTitle;

  /// Label of the first tab (the recipients list).
  String get recipientsTabLabel;

  /// Label of the second tab, read again each time [listenable] fires.
  String tabLabel();

  /// Label of the bar at the bottom of the first tab.
  String get forgetAllLabel;

  /// One more sentence for the Forget all dialog.
  String get forgetAllNote;

  /// The body of the second tab.
  Widget buildBody(BuildContext context);
}
