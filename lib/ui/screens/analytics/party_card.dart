import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'parts.dart';

/// §ANALYTICS.PARTY — the party (recipient) header shown in party mode: a slim
/// one-line pinned strip (~44px). The screen renders it ABOVE the scroll area,
/// so it stays on screen while the hero, chart and transactions scroll.
class AnalyticsPartyCard extends StatelessWidget {
  const AnalyticsPartyCard({
    super.key,
    required this.palette,
    required this.type,
    required this.name,
    required this.onClose,
  });

  final AppPalette palette;
  final String type;
  final String? name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final shown = name ?? sourceTypeName(type);
    final initials = shown
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return AppCard(
      palette: palette,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        key: const Key('analyticsPartyCard'),
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: palette.typeColor(type), shape: BoxShape.circle),
            child: Text(
              initials,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: palette.onTypeColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: shown,
                    style: TextStyle(fontWeight: FontWeight.w800, color: palette.ink),
                  ),
                  TextSpan(
                    text: ' · ${sourceTypeName(type)}',
                    style: TextStyle(color: palette.mutedInk),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          AnalyticsRoundButton(
            key: const Key('analyticsPartyClose'),
            size: 28,
            icon: Icons.close_rounded,
            iconSize: 14,
            tooltip: 'Show everyone',
            background: palette.track,
            foreground: palette.ink,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}
