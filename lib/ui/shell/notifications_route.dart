/// §SHELL.NOTIFICATIONS_ROUTE — the page behind [Routes.notifications]: builds
/// the Notifications page from the [NotificationsScope] and the route's
/// [NotificationsRouteArgs] (none = the All chip).
library;

import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/data/real_waiting_actions.dart';
import '../../autoread/data/real_waiting_repository.dart';
import '../../autoread/ui/waiting_section.dart' show WaitingActions;
import '../../domain/notifications/notif_chip.dart';
import '../screens/notifications/notifications_page.dart';
import 'notifications_scope.dart';
import 'routes.dart';

class NotificationsRoute extends StatelessWidget {
  const NotificationsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = NotificationsScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final args = ModalRoute.of(context)?.settings.arguments;
    var actions = const WaitingActions();
    if (kAutoReadCompiled) {
      final w = scope.waiting;
      if (w is RealWaitingRepository) actions = buildRealWaitingActions(context, w);
    }
    return NotificationsPage(
      news: scope.news,
      waiting: scope.waiting,
      waitingActions: actions,
      initialChip: args is NotificationsRouteArgs ? args.chip : NotifChip.all,
      // A tap on a notice or update row opens the existing Updates page, which
      // holds the full text.
      onOpenNews: (_) => Navigator.of(context).pushNamed(Routes.updates),
    );
  }
}
