import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'chrome_widgets.dart';

/// Chrome shared by every secondary page (Settings, Manage categories, Backup
/// and restore, Recently deleted, Privacy, Updates) — the secondary tier of
/// the two-tier chrome pattern: a top-left back-arrow icon-button instead of
/// the primary topbar's top-right Profile icon. 0.1.2 S9a: NO Add (+) button
/// on these pages (signed ST1); the Back button is `primary` / `onPrimary`.
///
/// **`followPalette` (T24):** opt-in palette chrome, mirroring
/// `PrimaryScaffold.followPhoneTheme`. Defaults to `false`, so Manage
/// Classifications and Recently Deleted stay exactly as today
/// ([AppColors.bg], the grey back button, no scrolled-under tint). `true`
/// (Profile, T24) drives the background, a seamless app bar (no divider/
/// elevation; a 7%-primary scrolled-under tint), a round `primary`/`onPrimary`
/// Back button, an `ink` title and the
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
              background: palette.primary,
              foreground: palette.onPrimary,
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
        body: body,
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
      body: body,
    );
  }
}
