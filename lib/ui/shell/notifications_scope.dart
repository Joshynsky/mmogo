/// §SHELL.NOTIFICATIONS_SCOPE — hands the Notifications page and the bell their
/// data without the page knowing where it comes from. `main.dart` places it
/// above `MaterialApp`; the integration slice swaps the adapters it passes.
///
/// A hook file (see `kAutoReadHookFiles`): it names the waiting repository
/// type, which is only ever read inside `if (kAutoReadCompiled)`.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../autoread/model/waiting_repository.dart';
import '../../domain/notifications/notifications_repository.dart';
import 'bell_counts.dart';

class NotificationsScope extends InheritedWidget {
  const NotificationsScope({
    super.key,
    required this.news,
    required this.counts,
    this.waiting,
    required super.child,
  });

  final NotificationsRepository news;

  /// Null in the standard build.
  final AutoReadWaitingRepository? waiting;

  /// What the bell shows now.
  final ValueListenable<BellCounts> counts;

  static NotificationsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationsScope>();

  @override
  bool updateShouldNotify(NotificationsScope old) =>
      old.news != news || old.waiting != waiting || old.counts != counts;
}
