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

  /// The text of the page's one "?" while the second tab is showing.
  RememberedExtraHelp get help;
}

/// A help sheet's title and paragraphs (plain strings; the page draws them).
class RememberedExtraHelp {
  const RememberedExtraHelp(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

/// The words of the Forget all dialog and its toast for one count (plain strings; counts only, never a
/// name).
class RememberedForgetAllText {
  const RememberedForgetAllText({required this.title, required this.body, required this.ok, required this.toast});
  final String title;
  final String body;

  /// The confirm button.
  final String ok;

  /// The toast after a successful Forget all.
  final String toast;
}

/// Optional: an extra tab that supplies its own Forget all words (0.2.2). [forgetAllText] gets the keys of
/// the remembered names the page will forget (never shown or logged) so the tab can count everyone the
/// Forget all removes, each person once; null = the page's own words (as without this interface). A
/// throw means the count could not be taken: the page shows its failure line and no dialog.
abstract class RememberedForgetAllCopy {
  Future<RememberedForgetAllText?> forgetAllText(List<String> nameKeys);
}

/// Optional (0.2.2 item 2 U-FORGET, B-5): an extra tab whose Forget all also removes people who are NOT
/// on the recipients list (for example people with only a rule), so the page can enable its Forget all
/// button when the list is empty but such people exist. [forgetAllExtraPeople] gets the same keys as
/// [RememberedForgetAllCopy.forgetAllText] and returns how many people Forget all removes ON TOP of
/// them, each once: a person who is already one of [nameKeys] is NOT counted again (the page adds the
/// names itself). So names + this = the dialog's count. A throw means the count is not known: the page
/// then leaves the button enabled and the dialog's own count decides (its failure line if that fails too).
abstract class RememberedForgetAllCount {
  Future<int> forgetAllExtraPeople(List<String> nameKeys);
}

/// The page's count getter for the people Forget all removes beyond [nameKeys]. Default 0 (names only)
/// when there is no extra tab or the tab does not implement [RememberedForgetAllCount]; a negative
/// answer is read as 0. Throws when the tab's count throws.
Future<int> rememberedForgetAllExtra(RememberedExtraTab? tab, List<String> nameKeys) async {
  if (tab is! RememberedForgetAllCount) return 0;
  final n = await (tab as RememberedForgetAllCount).forgetAllExtraPeople(nameKeys);
  return n < 0 ? 0 : n;
}

/// Optional: an extra tab that also wants to hear what happens on the recipients list, so what it keeps
/// about a name goes with the name. The page calls these AFTER the change was stored. Plain Dart; a
/// tab without it simply hears nothing. [key] is the remembered-name key (never shown or logged).
abstract class RememberedForgetHooks {
  /// One name was forgotten.
  Future<void> onNameForgotten(String key);

  /// A name was changed to Send Money.
  Future<void> onNameChangedToSendMoney(String key);

  /// Every name was forgotten.
  Future<void> onAllNamesForgotten();
}
