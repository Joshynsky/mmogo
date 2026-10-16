import 'package:flutter/material.dart';

import '../copy/data_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';

/// §UI.WHATSNEW.ENTRY — the one "What's new in mmogo 0.1.2" entry on the
/// Updates page (0.1.2 S11a, A2). SYNTHETIC: it is not a stored notice, so it
/// is not counted by the bell or the Settings dot. Same card look as
/// `NoticeCard`. The NEW pill is [showNew]; the button has its own key and
/// semantics label (the page also has "See what's new" buttons that open the
/// browser, so tests and screen readers must tell them apart).
class WhatsNewEntryCard extends StatelessWidget {
  const WhatsNewEntryCard({super.key, required this.showNew, required this.onOpen});

  final bool showNew;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('whatsNewEntry'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // S11b (CB5): the entry heading is a heading for a screen reader.
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    kWhatsNewPagerTitle,
                    key: const Key('whatsNewEntryTitle'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.3, color: palette.ink),
                  ),
                ),
              ),
              if (showNew) ...[
                const SizedBox(width: 8),
                Container(
                  key: const Key('whatsNewEntryPill'),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    kUpdatesNewPill.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: palette.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(kWhatsNewEntryBody, style: TextStyle(fontSize: 13, height: 1.5, color: palette.softInk)),
          const SizedBox(height: 10),
          Semantics(
            container: true,
            button: true,
            label: kWhatsNewPagerTitle,
            excludeSemantics: true,
            onTap: onOpen,
            child: SizedBox(
              height: kMinTapTarget,
              child: FilledButton(
                key: const Key('whatsNewEntryButton'),
                onPressed: onOpen,
                style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
                child: const Text(kWhatsNewEntryButton),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
