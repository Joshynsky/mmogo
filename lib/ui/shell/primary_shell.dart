import 'package:flutter/material.dart';

import '../../domain/home/home_period.dart';
import '../screens/analytics_screen.dart';
import '../screens/home_screen.dart';
import '../screens/paid_to_screen.dart';
import '../screens/settings_screen.dart';

/// F6 (T21 fix round): one change of the period LENGTH shared by Home and
/// Analytics. Home posts its own choice ([fromAnalytics] `false`); Analytics
/// posts only a length change to Day / Week / Month ([fromAnalytics] `true`).
/// Each page reacts only to the other's posts, so the last change wins.
class PeriodLengthChange {
  // Not const: every post is a distinct object, so a repeat still notifies.
  PeriodLengthChange(this.length, {required this.fromAnalytics});

  final HomePeriod length;
  final bool fromAnalytics;
}

/// A hand-off into the Analytics tab: an `int` (Home's transaction id) or an
/// [AnalyticsRouteArgs] (Paid to) — the same shapes as Analytics' route
/// arguments.
class AnalyticsRequest {
  AnalyticsRequest(this.args);

  final Object args;
}

/// The live state of the primary shell, shared with its pages.
class PrimaryShellController {
  PrimaryShellController(int initialIndex) : index = ValueNotifier(initialIndex);

  /// T22 nav order (PM direct decision, 2026-09-25): 0 Home, 1 Analytics,
  /// 2 Add (the FAB, never a tab), 3 Paid to, 4 Settings.
  static const analyticsIndex = 1;
  static const paidToIndex = 3;

  /// The visible nav slot (see [analyticsIndex] / [paidToIndex]).
  final ValueNotifier<int> index;

  /// F6: the latest shared period-length change (`null` = none yet).
  final ValueNotifier<PeriodLengthChange?> periodLength = ValueNotifier(null);

  /// F5: a pending hand-off for Analytics; it sets this back to `null` once
  /// handled.
  final ValueNotifier<AnalyticsRequest?> analyticsRequest = ValueNotifier(null);

  /// Bumped when something outside a page changed the data it shows (Add
  /// saved a transaction). Every live page then re-queries silently.
  final ValueNotifier<int> dataRevision = ValueNotifier(0);

  void dataChanged() => dataRevision.value++;

  /// The route the shell lives in (so a page pushed over it, e.g. Add, can
  /// pop back to it).
  ModalRoute<Object?>? route;

  void select(int i) {
    if (i == 2) return; // Add is a pushed page, never a shell tab.
    index.value = i;
  }

  /// Switches to Analytics and retargets it (no second Analytics is stacked).
  void openAnalytics(Object args) {
    analyticsRequest.value = AnalyticsRequest(args);
    index.value = analyticsIndex;
  }

  void dispose() {
    index.dispose();
    periodLength.dispose();
    analyticsRequest.dispose();
    dataRevision.dispose();
  }
}

/// F5 (T21 fix round, replaces F1): Home, Analytics, Paid to and Settings
/// live side by side in one route and stay alive. A tab switch is instant
/// (no route transition) and each page keeps its own state — period,
/// filters, tab, scroll. Each page is built on its first visit. Add (the
/// FAB) is still a page pushed on top. Android back: a non-Home tab goes to
/// Home; Home leaves the app.
///
/// Every page still builds its own [PrimaryScaffold] (its own
/// `followPhoneTheme` and system-bar region); only the visible one paints.
class PrimaryShell extends StatefulWidget {
  const PrimaryShell({super.key, this.initialIndex = 0, this.pages});

  final int initialIndex;

  /// Test seam: the pages by nav index (0 Home, 1 Analytics, 3 Paid to,
  /// 4 Settings). `null` = the real ones.
  final Map<int, Widget>? pages;

  static PrimaryShellController? _active;

  /// The shell of the page this [context] belongs to, if any.
  static PrimaryShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ShellScope>()?.controller;

  /// The app's live shell, for pages pushed over it (Add, the secondary
  /// pages' mini-FAB). `null` when there is none (e.g. a lone test page).
  static PrimaryShellController? get active {
    final a = _active;
    return a != null && (a.route?.isActive ?? false) ? a : null;
  }

  @override
  State<PrimaryShell> createState() => _PrimaryShellState();
}

class _PrimaryShellState extends State<PrimaryShell> {
  late final PrimaryShellController _controller = PrimaryShellController(widget.initialIndex == 2 ? 0 : widget.initialIndex);
  late final Set<int> _built = {_controller.index.value};

  @override
  void initState() {
    super.initState();
    PrimaryShell._active = _controller;
    _controller.index.addListener(_onIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    if (PrimaryShell._active == _controller) PrimaryShell._active = null;
    _controller.index.removeListener(_onIndex);
    _controller.dispose();
    super.dispose();
  }

  void _onIndex() => setState(() => _built.add(_controller.index.value));

  Widget _page(int i) {
    final custom = widget.pages?[i];
    if (custom != null) return custom;
    return switch (i) {
      0 => const HomeScreen(),
      PrimaryShellController.analyticsIndex => const AnalyticsScreen(),
      PrimaryShellController.paidToIndex => const PaidToScreen(),
      _ => const SettingsScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final index = _controller.index.value;
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.select(0);
      },
      child: _ShellScope(
        controller: _controller,
        child: IndexedStack(
          index: index,
          sizing: StackFit.expand,
          children: [
            for (var i = 0; i < 5; i++)
              if (i == 2 || !_built.contains(i))
                const SizedBox.shrink()
              else
                TickerMode(
                  enabled: i == index,
                  child: KeyedSubtree(key: ValueKey('primaryShellPage-$i'), child: _page(i)),
                ),
          ],
        ),
      ),
    );
  }
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({required this.controller, required super.child});

  final PrimaryShellController controller;

  @override
  bool updateShouldNotify(_ShellScope old) => old.controller != controller;
}

/// F5: a primary page's silent refresh when its tab becomes visible again —
/// re-query without resetting the page's state.
mixin PrimaryTabRefresh<T extends StatefulWidget> on State<T> {
  /// This page's nav index.
  int get primaryTabIndex;

  /// Called when the tab becomes visible again (not on first build).
  void onPrimaryTabShown();

  PrimaryShellController? _tabShell;
  int? _lastTabIndex;

  /// The shell this page lives in, if any.
  PrimaryShellController? get primaryShell => _tabShell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = PrimaryShell.maybeOf(context);
    if (shell == _tabShell) return;
    _tabShell?.index.removeListener(_onTabIndex);
    _tabShell?.dataRevision.removeListener(_onDataChanged);
    _tabShell = shell;
    _lastTabIndex = shell?.index.value;
    shell?.index.addListener(_onTabIndex);
    shell?.dataRevision.addListener(_onDataChanged);
  }

  // Add saved a row: re-query now, even while this tab is hidden, so it is
  // already current when shown.
  void _onDataChanged() {
    if (mounted) onPrimaryTabShown();
  }

  void _onTabIndex() {
    final i = _tabShell!.index.value;
    final was = _lastTabIndex;
    _lastTabIndex = i;
    if (mounted && i == primaryTabIndex && was != i) onPrimaryTabShown();
  }

  @override
  void dispose() {
    _tabShell?.index.removeListener(_onTabIndex);
    _tabShell?.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }
}
