/// §SHELL.NOTIFICATIONS_ROUTE — the page behind [Routes.notifications]: builds
/// the Notifications page from the [NotificationsScope] and the route's
/// [NotificationsRouteArgs] (none = the To do chip).
library;

import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/data/real_waiting_actions.dart';
import '../../autoread/data/real_waiting_repository.dart';
import '../../autoread/ui/todo_choose.dart' show ChoosingIds;
import '../../autoread/ui/waiting_section.dart' show WaitingActions;
import '../../domain/notifications/news_item.dart';
import '../../domain/notifications/notif_chip.dart';
import '../screens/notifications/notifications_page.dart';
import '../whats_new/whats_new_hook.dart' show openWhatsNewToRead;
import 'notifications_scope.dart';
import 'routes.dart';

class NotificationsRoute extends StatefulWidget {
  const NotificationsRoute({super.key});

  @override
  State<NotificationsRoute> createState() => _NotificationsRouteState();
}

class _NotificationsRouteState extends State<NotificationsRoute> {
  // Page state that must outlive a rebuild: the rows parsed on this visit and
  // the one-line note at the top of the To do view (autoread build only).
  final ChoosingIds _choosing = ChoosingIds();
  final ValueNotifier<String?> _note = ValueNotifier<String?>(null);

  bool _undecidedRequested = false;

  @override
  void dispose() {
    _choosing.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = NotificationsScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final args = ModalRoute.of(context)?.settings.arguments;
    var actions = const WaitingActions();
    if (kAutoReadCompiled) {
      final w = scope.waiting;
      if (w is RealWaitingRepository) {
        actions = buildRealWaitingActions(context, w, choosing: _choosing, note: _note);
        if (!_undecidedRequested) {
          _undecidedRequested = true;
          w.refreshUndecided();
        }
      }
    }
    return NotificationsPage(
      news: scope.news,
      waiting: scope.waiting,
      waitingActions: actions,
      quietNote: kAutoReadCompiled ? _note : null,
      initialChip: args is NotificationsRouteArgs ? args.chip : NotifChip.todo,
      focusId: args is NotificationsRouteArgs ? args.focusId : null,
      // A tap on a notice or update row opens the existing Updates page, which
      // holds the full text; the What's new row opens the pages to read.
      onOpenNews: (n) {
        if (n.kind == NewsKind.whatsNew) {
          openWhatsNewToRead(context);
          return;
        }
        Navigator.of(context).pushNamed(Routes.updates);
      },
    );
  }
}
