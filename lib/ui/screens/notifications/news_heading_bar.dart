/// The News heading line: "News (n)" and the Unread | Read switch on ONE
/// row. n is the unread count in both views. Shared by both flavors.
library;

import 'package:flutter/material.dart';

import '../../../domain/notifications/news_logic.dart' show capCount;
import '../../copy/notifications_copy.dart';

class NewsHeadingBar extends StatelessWidget {
  const NewsHeadingBar({
    super.key,
    required this.unreadCount,
    required this.readView,
    required this.onChanged,
  });

  final int unreadCount;
  final bool readView;

  /// true = Read view chosen, false = Unread view chosen.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              newsHeadingWithCount(capCount(unreadCount)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: kNewsSwitchLabel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Option(
                label: kNewsSwitchUnread,
                selected: !readView,
                onTap: () => onChanged(false),
              ),
              const SizedBox(width: 4),
              _Option(
                label: kNewsSwitchRead,
                selected: readView,
                onTap: () => onChanged(true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Not colour alone: a check mark and bold on the chosen one.
                  if (selected) ...[
                    Icon(Icons.check, size: 16, color: fg),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
