import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../data/updates/updates_inbox.dart';
import '../theme/app_colors.dart';
import 'chrome_widgets.dart';
import 'primary_shell.dart';
import 'routes.dart';

/// Chrome shared by all 5 primary destinations (Home, Analytics, Add,
/// Paid to, Profile) — the primary tier of the two-tier chrome pattern:
/// a top bar (title + top-right bell only, B48) plus the fixed 5-item
/// bottom nav with a centered, permanently-raised FAB (the Add slot).
///
/// **Seamless top bar on every primary page (T20; PM direct decision,
/// 2026-09-24):** the bar has no divider line and
/// no fill of its own — it uses the page background, so the title flows
/// straight into the first card. Only when content scrolls under it does it
/// gain a subtle tint plus a soft shadow (Material 3 "scrolled-under").
///
/// **Colours (T20):** the chrome (top bar, bottom nav, FAB, Profile button)
/// uses Ocean & Sun ([AppPalette]) on every primary page. Whether it also
/// follows the phone's dark setting is per page, via [followPhoneTheme]:
/// only reworked pages (Home today) pass `true`; the rest stay pinned to
/// [AppPalette.light] and keep their current body background
/// ([AppColors.bg]), so nothing half-darkens.
///
/// Every primary screen wraps its body in this one widget rather than each
/// screen re-declaring its own Scaffold/AppBar/nav-bar, so the chrome
/// itself has exactly one implementation to keep consistent.
class PrimaryScaffold extends StatelessWidget {
  const PrimaryScaffold({
    super.key,
    required this.title,
    required this.activeIndex,
    required this.body,
    this.followPhoneTheme = false,
    this.fabTourKey,
  });

  final String title;

  /// Lets a page's coach tour spotlight the centre + button.
  final GlobalKey? fabTourKey;

  /// Index into [Routes.primaryOrder] (0=Home,1=Analytics,2=Add,3=Paid to,
  /// 4=Profile; T22 order, B48 Profile) — which nav slot is the "you are here" highlight.
  final int activeIndex;

  final Widget body;

  /// `true` for a reworked page whose body follows the phone's light/dark
  /// setting ([AppPalette.of]); the chrome and page background then follow
  /// it too. `false` (default) pins the chrome to [AppPalette.light] and the
  /// page background to today's [AppColors.bg].
  final bool followPhoneTheme;

  void _goToPrimary(BuildContext context, int index) {
    if (index == activeIndex) return;
    // F5: inside the [PrimaryShell] a tab switch is instant and keeps every
    // page alive; Add is pushed on top of the shell.
    final shell = PrimaryShell.maybeOf(context);
    if (shell != null) {
      if (index == 2) {
        Navigator.of(context).pushNamed(Routes.add);
      } else {
        shell.select(index);
      }
      return;
    }
    // A primary page pushed over the shell (Add): back to the shell's tab.
    final active = PrimaryShell.active;
    if (active != null) {
      Navigator.of(context).popUntil((route) => route == active.route);
      active.select(index);
      return;
    }
    // No shell (a lone page): reset to a single-root stack, as before.
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.primaryOrder[index], (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = followPhoneTheme ? AppPalette.of(context) : AppPalette.light;
    final pageBg = followPhoneTheme ? palette.background : AppColors.bg;
    // Scrolled-under: a faint Ocean wash over the page background (7%, the
    // Analytics mock's `.appbar.under`, T21).
    final scrolledBg = Color.alphaBlend(palette.primary.withValues(alpha: 0.07), pageBg);

    // T21 system bars: the AppBar sets the status bar (top edge); this region
    // covers the bottom edge, where Flutter reads the gesture/nav bar colour.
    // F5: Android back from a primary page pushed over the shell (Add)
    // lands on Home, like back from any non-Home tab.
    final overShell = PrimaryShell.maybeOf(context) == null ? PrimaryShell.active : null;
    final scaffold = AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.systemOverlayStyle,
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          // Primary destinations never show a back arrow, per
          // the two-tier chrome pattern -- only secondary
          // pages do. Without this, a primary screen reached via a normal
          // (stack-preserving) `pushNamed` -- e.g. Home's recent-transaction
          // tap into Analytics, T4 -- would pick up Flutter's automatic
          // back arrow on top of the full bottom nav.
          automaticallyImplyLeading: false,
          backgroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.scrolledUnder) ? scrolledBg : pageBg,
          ),
          foregroundColor: palette.ink,
          elevation: 0,
          scrolledUnderElevation: 2,
          shadowColor: const Color(0x33000000),
          surfaceTintColor: Colors.transparent,
          shape: const Border(), // no divider line
          systemOverlayStyle: palette.systemOverlayStyle,
          titleSpacing: 16,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.18, color: palette.ink),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // B48: the bell is the only top-right button (the Help "?"
                  // moved into Profile; Profile is a bottom-nav tab).
                  // B27: opens the Updates page; a red dot while any
                  // update notice is unread.
                  ValueListenableBuilder<int>(
                    valueListenable: UpdatesInbox.instance.unreadCount,
                    builder: (context, unread, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconCircleButton(
                          icon: Icons.notifications_none_rounded,
                          tooltip: unread > 0 ? 'Updates, $unread unread' : 'Updates',
                          size: 36,
                          background: palette.card,
                          foreground: palette.ink,
                          onTap: () => Navigator.of(context).pushNamed(Routes.updates),
                        ),
                        if (unread > 0)
                          Positioned(
                            top: 5,
                            right: 6,
                            child: IgnorePointer(
                              child: Container(
                                key: const Key('bellUnreadDot'),
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: palette.diffUp,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: palette.card, width: 2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: body,
        bottomNavigationBar: _PrimaryBottomNav(
          palette: palette,
          activeIndex: activeIndex,
          fabTourKey: fabTourKey,
          onTap: (i) => _goToPrimary(context, i),
        ),
      ),
    );
    if (overShell == null) return scaffold;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) overShell.select(0);
      },
      child: scaffold,
    );
  }
}

class _PrimaryBottomNav extends StatelessWidget {
  const _PrimaryBottomNav({required this.palette, required this.activeIndex, required this.onTap, this.fabTourKey});

  final AppPalette palette;
  final int activeIndex;
  final GlobalKey? fabTourKey;
  final ValueChanged<int> onTap;

  static const _navHeight = 66.0;

  /// The nav's layout box is [_navHeight] + 14 tall (the body ends there).
  static const _boxHeight = _navHeight + 14;

  /// How far the FAB's ring rises above that box: the ring's top is 29px
  /// above the nav (mock `.fab` top:-24px plus the 5px ring), i.e. 15px above
  /// the 80px box.
  static const _fabOverhang = 29 - 14.0;

  static const _icons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    null, // FAB slot, rendered separately
    Icons.groups_rounded,
    Icons.person_rounded,
  ];
  // T22: Home · Analytics · + · Paid to · Settings; B48 (PM 2026-10-01):
  // the last tab is Profile (Settings opens from inside it).
  static const _labels = ['Home', 'Analytics', 'Add', 'Paid to', 'Profile'];

  @override
  Widget build(BuildContext context) {
    // T21 FAB fix (backlog "FAB top edge outside its hit area"): the box
    // still lays out at [_boxHeight], but its hit area reaches up over the
    // FAB's overhang, so the whole visible FAB and ring take the tap instead
    // of letting it fall through to the row underneath.
    return _OverhangHitBox(
      height: _boxHeight,
      overhang: _fabOverhang,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            key: const Key('primaryBottomNav'),
            height: _navHeight,
            decoration: BoxDecoration(
              color: palette.card,
              border: Border(top: BorderSide(color: palette.line)),
            ),
            // Five equal slots (the middle one is the space under the FAB),
            // so long labels or large text never overflow the row.
            child: Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: i == 2
                        ? const SizedBox.shrink()
                        : _NavItem(
                            icon: _icons[i]!,
                            label: _labels[i],
                            color: activeIndex == i ? palette.primary : palette.mutedInk,
                            onTap: () => onTap(i),
                          ),
                  ),
              ],
            ),
          ),
          // Mock `.fab`: the 54px button's top sits 24px above the nav, and
          // its 5px ring 29px above; the ring's bottom is then 31px above
          // the nav's bottom edge (66 - (64 - 29)).
          Positioned(
            bottom: _navHeight - (64 - 29),
            child: KeyedSubtree(
              key: fabTourKey,
              child: _Fab(palette: palette, active: activeIndex == 2, onTap: () => onTap(2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays its child out [overhang] px taller than its own [height], drawn
/// upward over whatever sits above, and — unlike a plain overflowing Stack —
/// hit-tests that overhang too. Only the child's real content takes hits
/// there (e.g. the FAB); empty overhang space still falls through.
class _OverhangHitBox extends SingleChildRenderObjectWidget {
  const _OverhangHitBox({required this.height, required this.overhang, required Widget super.child});

  final double height;
  final double overhang;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverhangHitBox(height, overhang);

  @override
  void updateRenderObject(BuildContext context, _RenderOverhangHitBox renderObject) {
    renderObject
      ..boxHeight = height
      ..overhang = overhang;
  }
}

class _RenderOverhangHitBox extends RenderShiftedBox {
  _RenderOverhangHitBox(this._boxHeight, this._overhang) : super(null);

  double _boxHeight;
  set boxHeight(double v) {
    if (v == _boxHeight) return;
    _boxHeight = v;
    markNeedsLayout();
  }

  double _overhang;
  set overhang(double v) {
    if (v == _overhang) return;
    _overhang = v;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, _boxHeight));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    size = constraints.constrain(Size(width, _boxHeight));
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.tightFor(width: size.width, height: _boxHeight + _overhang));
    (child.parentData! as BoxParentData).offset = Offset(0, -_overhang);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final area = Rect.fromLTRB(0, -_overhang, size.width, size.height);
    if (!area.contains(position)) return false;
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// The centred Add button: a 54px Ocean circle with an on-primary "+",
/// ringed by 5px of the nav's card colour (mock `.fab`). The ring is part of
/// the button (T21): a tap anywhere on the visible disc opens Add.
class _Fab extends StatelessWidget {
  const _Fab({required this.palette, required this.active, required this.onTap});

  final AppPalette palette;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('primaryFabRing'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: palette.card, shape: BoxShape.circle),
        child: Material(
          key: const Key('primaryFab'),
          color: palette.primary,
          // On Add itself: a ring in the deep ocean shade marks "you are here".
          shape: CircleBorder(side: active ? BorderSide(color: palette.deep, width: 2) : BorderSide.none),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 54, height: 54, child: Icon(Icons.add, color: palette.onPrimary, size: 26)),
          ),
        ),
      ),
    );
  }
}
