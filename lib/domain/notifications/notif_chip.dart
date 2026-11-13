/// The filter chips of the Notifications page.
library;

enum NotifChip {
  all,
  parse,
  categorize,
  news,

  /// The single To do view. The old values above stay so saved route
  /// arguments and old callers keep compiling; they all open To do.
  todo;

  /// True for every chip that opens the To do view (everything but News).
  bool get opensTodo => this != NotifChip.news;
}

/// The two chips the auto-read Notifications page shows.
const List<NotifChip> todoNewsChips = [NotifChip.todo, NotifChip.news];

/// The chips to show. Without the auto-read feature there is only News, which
/// means NO chip row is shown (the page is just the News list). With it: To do
/// and News.
List<NotifChip> availableChips({required bool autoReadCompiled}) =>
    autoReadCompiled ? todoNewsChips : [NotifChip.news];
