import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An [AlertDialog] that follows the chosen palette and the phone's light or
/// dark setting, like the bottom sheets do.
///
/// `AppTheme` is pinned to a light Material theme (see `main.dart`), so a
/// plain [AlertDialog] is always a pale card with dark text, even on a dark
/// phone. Here the card, the text, the buttons and any text field inside take
/// the palette's colours instead. Use it in place of [AlertDialog] (same
/// `key`, `title`, `content` and `actions`).
class PaletteAlertDialog extends StatelessWidget {
  const PaletteAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.insetPadding,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Optional tighter paddings (the First day dialog). Null keeps the Material
  /// default, so every other dialog is unchanged.
  final EdgeInsets? insetPadding;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final base = Theme.of(context);
    final scheme = base.colorScheme.copyWith(
      primary: palette.primary,
      onSurface: palette.ink,
      onSurfaceVariant: palette.softInk,
      surface: palette.card,
      outline: palette.mutedInk,
      outlineVariant: palette.mutedInk,
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        textTheme: base.textTheme.apply(bodyColor: palette.ink, displayColor: palette.ink),
        textSelectionTheme: TextSelectionThemeData(cursorColor: palette.primary),
      ),
      child: AlertDialog(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 22, height: 1.25, color: palette.ink),
        contentTextStyle: TextStyle(fontSize: 14, height: 1.4, color: palette.ink),
        title: title,
        content: content,
        actions: actions,
        insetPadding: insetPadding ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        titlePadding: titlePadding,
        contentPadding: contentPadding,
        actionsPadding: actionsPadding,
      ),
    );
  }
}
