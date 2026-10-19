/// §SHELL.BELL_BUTTON — the primary top bar's bell: the F7 [NotifBell] fed by
/// the [NotificationsScope] counts. Tapping it opens the Notifications page on
/// the All chip (the signed `notifications-notes.md`: "Bell = All"; in the
/// standard build the page then shows News, its only list).
///
/// The red unread dot of the old bell is gone: the signed bell notes say red is
/// not used; the update arrow, the new-notice star, the number pill and the
/// diamond replace it.
///
/// A hook file (see `kAutoReadHookFiles`): the pill, the diamond and their
/// spoken words are reached only inside `if (kAutoReadCompiled)`.
library;

import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/ui/bell_spoken.dart';
import '../../data/updates/updates_inbox.dart';
import '../copy/bell_copy.dart';
import '../widgets/notif_bell.dart';
import 'bell_counts.dart';
import 'notifications_scope.dart';
import 'routes.dart';
import 'updates_news_repository.dart';

/// The counts of the scope, or (no scope above, as in widget tests of single
/// screens) the ones the real inbox gives.
class _FallbackCounts {
  static final UpdatesNewsRepository _repo = UpdatesNewsRepository(UpdatesInbox.instance, loadOnWatch: false);
  static final BellCountsTracker tracker = BellCountsTracker(news: _repo.watchNews());
}

/// The spoken label for [c] ("Notifications, ..."). Standard build: update and
/// new notice only.
String bellLabelFor(BellCounts c) {
  if (kAutoReadCompiled) {
    return bellSpokenLabelAutoRead(
      update: c.update,
      newNotice: c.newNotice,
      readyToParse: c.readyToParse,
      waiting: c.waiting,
    );
  }
  return bellSpokenLabel(update: c.update, newNotice: c.newNotice);
}

class BellButton extends StatelessWidget {
  const BellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final listenable = NotificationsScope.maybeOf(context)?.counts ?? _FallbackCounts.tracker.value;
    return ValueListenableBuilder<BellCounts>(
      valueListenable: listenable,
      builder: (context, c, _) => NotifBell(
        arrow: c.update,
        star: c.newNotice,
        pillCount: kAutoReadCompiled ? c.waiting : null,
        diamondCount: kAutoReadCompiled ? c.readyToParse : null,
        spokenLabel: bellLabelFor(c),
        onTap: () => Navigator.of(context).pushNamed(Routes.notifications),
      ),
    );
  }
}
