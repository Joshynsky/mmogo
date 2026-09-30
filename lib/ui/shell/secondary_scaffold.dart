import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'chrome_widgets.dart';
import 'primary_shell.dart';
import 'routes.dart';

/// Chrome shared by every secondary page (Profile, Manage Classifications,
/// Recently Deleted) — the secondary tier of the two-tier chrome pattern: a
/// top-left back-arrow icon-button instead of the primary topbar's
/// top-right Profile icon, plus a small floating mini-FAB (bottom-right)
/// so Add stays reachable without repeating the full 5-item bottom nav on
/// a page that isn't meant to read as a primary destination.
///
/// **`followPalette` (T24):** opt-in palette chrome, mirroring
/// `PrimaryScaffold.followPhoneTheme`. Defaults to `false`, so Manage
/// Classifications and Recently Deleted stay exactly as today
/// ([AppColors.bg], the grey back button, no scrolled-under tint). `true`
/// (Profile, T24) drives the background, a seamless app bar (no divider/
/// elevation; a 7%-primary scrolled-under tint), a round `backBg`/`backInk`
/// Back button, an `ink` title, a `primary`/`onPrimary` mini-FAB and the
/// system bars from `AppPalette.of(context).systemOverlayStyle`.
class SecondaryScaffold extends StatelessWidget {
  const SecondaryScaffold({super.key, required this.title, required this.body, this.followPalette = false});

  final String title;
  final Widget body;
  final bool followPalette;

  @override
  Widget build(BuildContext context) {
    if (!followPalette) return _buildLegacy(context);

    final palette = AppPalette.of(context);
    final scrolledBg = Color.alphaBlend(palette.primary.withValues(alpha: 0.07), palette.background);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.systemOverlayStyle,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: IconCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              background: palette.backBg,
              foreground: palette.backInk,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          leadingWidth: 56,
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: palette.ink),
          ),
          backgroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.scrolledUnder) ? scrolledBg : palette.background,
          ),
          foregroundColor: palette.ink,
          elevation: 0,
          scrolledUnderElevation: 2,
          shadowColor: const Color(0x33000000),
          surfaceTintColor: Colors.transparent,
          shape: const Border(), // no divider line
          systemOverlayStyle: palette.systemOverlayStyle,
        ),
        body: Stack(
          children: [
            body,
            Positioned(
              right: 18,
              bottom: 18,
              child: _MiniFab(
                color: palette.primary,
                onColor: palette.onPrimary,
                onTap: () => _openAdd(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacy(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconCircleButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        leadingWidth: 56,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Stack(
        children: [
          body,
          Positioned(
            right: 18,
            bottom: 18,
            child: _MiniFab(
              color: AppColors.primary,
              onColor: Colors.white,
              onTap: () => _openAdd(context),
            ),
          ),
        ],
      ),
    );
  }

  // Add is reachable from anywhere — clears back to a single-root primary stack, same as
  // tapping Add from the primary bar. F5: with a live shell, keep it (and
  // its pages' state) underneath Add instead of clearing the stack.
  void _openAdd(BuildContext context) {
    final shell = PrimaryShell.active;
    if (shell != null) {
      Navigator.of(context)
        ..popUntil((route) => route == shell.route)
        ..pushNamed(Routes.add);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.add, (route) => false);
  }
}

class _MiniFab extends StatelessWidget {
  const _MiniFab({required this.color, required this.onColor, required this.onTap});

  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: color.withValues(alpha: 0.45),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.add, color: onColor, size: 26),
        ),
      ),
    );
  }
}
