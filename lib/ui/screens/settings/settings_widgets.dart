import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Shared building blocks for the Settings page's sections (moved verbatim
/// from the old single-file `settings_screen.dart`; names made public only so
/// the section files can use them).

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key, required this.palette, this.tag});

  final String text;
  final AppPalette palette;

  /// A small amber tag after the label ("careful", mock `.careful`).
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: palette.mutedInk),
            ),
          ),
          if (tag != null)
            Container(
              key: const Key('settingsCarefulTag'),
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFFFB703), borderRadius: BorderRadius.circular(5)),
              child: Text(
                tag!,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Color(0xFF3A2A00)),
              ),
            ),
        ],
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
    this.trailingIcon = Icons.chevron_right,
    this.value,
    this.redTag,
    this.focusNode,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  /// The arrow at the end: a chevron for in-app pages, "open in new" for rows
  /// that leave the app (Send feedback).
  final IconData trailingIcon;
  final bool first;

  /// The current choice, shown before the chevron (First day of the week).
  final String? value;

  /// A small red tag before the arrow ("Permanent", Delete data): the
  /// destructive red with its own text colour, so it reads in dark.
  final String? redTag;

  /// Lets the caller return focus to this row (after a sheet closes).
  final FocusNode? focusNode;

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
        focusNode: focusNode,
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
          constraints: const BoxConstraints(minHeight: 44),
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
              if (redTag != null)
                Container(
                  key: const Key('settingsRowRedTag'),
                  margin: const EdgeInsets.only(left: 8, right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: palette.diffUp, borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    redTag!,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: palette.onDelete),
                  ),
                ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(
                    value!,
                    key: const Key('settingsRowValue'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.mutedInk),
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
              if (onTap != null) Icon(trailingIcon, size: 18, color: palette.mutedInk),
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

/// A row with the icon tile and a title, no chevron and no tap of its own: it
/// heads a control that sits under it (a segmented choice) or beside it.
class SettingsHeadRow extends StatelessWidget {
  const SettingsHeadRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.first = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// A control at the end of the row (the Appearance icons).
  final Widget? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
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
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// A muted explanatory paragraph inside a card (mock `.shelp` / `.snote`).
class SettingsHelp extends StatelessWidget {
  const SettingsHelp(this.text, {super.key, required this.palette, this.bold = false, this.padding});

  final String text;
  final AppPalette palette;

  /// The darker, bolder variant (mock `.swarn`).
  final bool bold;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: bold ? palette.ink : palette.mutedInk,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// A two-or-three way choice drawn as a track of buttons (mock `.sseg`).
/// One radio group: the chosen button is filled, each is at least 44 high.
class SettingsSegment<T> extends StatelessWidget {
  const SettingsSegment({
    super.key,
    required this.palette,
    required this.label,
    required this.keyPrefix,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final AppPalette palette;

  /// The group's spoken name.
  final String label;

  /// Each button's key is `<keyPrefix>-<option name>`.
  final String keyPrefix;
  final List<(T value, String name, String text)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = palette.brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: label,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: dark ? palette.card : palette.track, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            for (final (v, name, text) in options)
              Expanded(
                child: Semantics(
                  button: true,
                  inMutuallyExclusiveGroup: true,
                  selected: v == value,
                  label: text,
                  excludeSemantics: true,
                  child: Material(
                    color: v == value ? (dark ? palette.line : palette.card) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: Key('$keyPrefix-$name'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onChanged(v),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: v == value ? palette.ink : palette.mutedInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
