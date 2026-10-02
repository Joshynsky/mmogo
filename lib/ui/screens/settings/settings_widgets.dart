import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Shared building blocks for the Settings page's sections (moved verbatim
/// from the old single-file `settings_screen.dart`; names made public only so
/// the section files can use them).

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key, required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: palette.mutedInk),
      ),
    );
  }
}

/// A rounded, palette-coloured card (mock `.acard`): the same shape Paid to
/// (T22) already uses for its own cards.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class SettingsLink extends StatelessWidget {
  const SettingsLink({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.first = false,
    this.warningDot = false,
    this.unreadDot = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool first;

  /// A small amber dot before the chevron (auto-backup paused).
  final bool warningDot;

  /// A small red dot before the chevron (an unread update notice).
  final bool unreadDot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SettingsRowIcon(icon: icon, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                  ],
                ),
              ),
              if (warningDot)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    key: const Key('settingsRowWarningDot'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: palette.sun, shape: BoxShape.circle),
                  ),
                ),
              if (unreadDot)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    key: const Key('settingsRowUnreadDot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: palette.diffUp, shape: BoxShape.circle),
                  ),
                ),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: palette.mutedInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// A `SettingsLink`-shaped row for a boolean preference: same icon/label/
/// subtitle styling, but a trailing `Switch` (state the user toggles in
/// place) instead of a chevron.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.first = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SettingsRowIcon(icon: icon, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: palette.onPrimary,
                activeTrackColor: palette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rounded icon tile at the start of a settings row (mock `.srow .ic`).
class SettingsRowIcon extends StatelessWidget {
  const SettingsRowIcon({super.key, required this.icon, required this.palette});

  final IconData icon;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.tint, borderRadius: const BorderRadius.all(Radius.circular(10))),
      child: Icon(icon, size: 18, color: palette.tintInk),
    );
  }
}
