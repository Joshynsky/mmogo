/// The filter chips of the Notifications page.
library;

enum NotifChip { all, parse, categorize, news }

/// The chips to show. Without the auto-read feature there is only News, which
/// means NO chip row is shown (the page is just the News list).
List<NotifChip> availableChips({required bool autoReadCompiled}) =>
    autoReadCompiled ? List.of(NotifChip.values) : [NotifChip.news];
