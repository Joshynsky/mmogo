import 'package:flutter/material.dart';

import '../../widgets/highlight_pulse.dart';

/// §SETTINGS.ROW_TARGET: what a Settings search pick does to the page. The Settings screen holds the picked row id and a
/// counter; every row that can be found is wrapped in a [SettingsRowTarget] with its search-entry id. The row whose id was
/// picked scrolls itself into view and pulses (a [HighlightPulse] started fresh), so a second pick of the same row pulses again.
class SettingsJumpScope extends InheritedWidget {
  const SettingsJumpScope({super.key, required this.pulseId, required this.serial, required super.child});

  /// The id of the row to pulse now (null = none).
  final String? pulseId;

  /// Bumped on every pick, so the same row pulses again.
  final int serial;

  static SettingsJumpScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsJumpScope>();

  @override
  bool updateShouldNotify(SettingsJumpScope old) => old.pulseId != pulseId || old.serial != serial;
}

/// Wraps one findable row. Outside a [SettingsJumpScope] it is just the child.
/// [alsoFor]: other entry ids that land on this row (a row the page does not show now, e.g. "Hide details after" while
/// alerts are generic, lands on the row that holds it).
class SettingsRowTarget extends StatelessWidget {
  const SettingsRowTarget({super.key, required this.id, required this.child, this.alsoFor = const {}});

  final String id;
  final Set<String> alsoFor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsJumpScope.maybeOf(context);
    if (scope == null) return child;
    final on = scope.pulseId == id || alsoFor.contains(scope.pulseId);
    return HighlightPulse(key: ValueKey(on ? '$id#${scope.serial}' : id), active: on, child: child);
  }
}
