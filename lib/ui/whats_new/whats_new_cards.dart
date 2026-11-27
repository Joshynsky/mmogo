import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/ui/whats_new_autoread_copy.dart';
import '../copy/whats_new_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';
import 'whats_new_items.dart';

/// §UI.WHATSNEW.CARDS — the banner and the accordion row of the What's-new page (0.1.2 A5a; the
/// items and their words are in `whats_new_items.dart`). A hook file (see `kAutoReadHookFiles`): the
/// auto-read build's banner is reached only inside `if (kAutoReadCompiled)`.
///
/// The banner at the very top: a tinted note saying which version this is. Both builds' banners
/// end with a link that opens the install guide (0.2.2).
class WhatsNewBanner extends StatelessWidget {
  const WhatsNewBanner({super.key, required this.palette, required this.onOpenSite});

  final AppPalette palette;
  final VoidCallback onOpenSite;

  @override
  Widget build(BuildContext context) {
    final head = kAutoReadCompiled ? kWhatsNewAutoBannerHead : kWhatsNewBannerHead;
    final body = kAutoReadCompiled ? kWhatsNewAutoBannerBody : kWhatsNewBannerBody;
    return Container(
      key: const Key('whatsNewBanner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            head,
            key: const Key('whatsNewBannerHead'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.4, color: palette.tintInk),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            key: const Key('whatsNewBannerBody'),
            style: TextStyle(fontSize: 13, height: 1.5, color: palette.tintInk),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('whatsNewBannerLink'),
              onPressed: onOpenSite,
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                padding: EdgeInsets.zero,
                foregroundColor: palette.tintInk,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(
                kAutoReadCompiled ? kWhatsNewAutoBannerLink : kWhatsNewBannerLink,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One accordion row. Closed: number, title and the one-line summary. Open:
/// number and title, then the full text (the summary is not repeated). The
/// whole header is the button (56 high, at least 44 wide) and says whether the
/// row is open.
class WhatsNewItemView extends StatelessWidget {
  const WhatsNewItemView({
    super.key,
    required this.item,
    required this.number,
    required this.open,
    required this.palette,
    required this.onToggle,
    this.onOpenSettings,
    this.onOpenBackup,
  });

  final WhatsNewItem item;

  /// 1-based, as shown in the round badge.
  final int number;
  final bool open;
  final AppPalette palette;
  final VoidCallback onToggle;

  /// "Change in Settings" (Weeks) and "Open Backup and restore" (Backups):
  /// injected, they push the route OVER the page and mark nothing seen.
  final void Function(String? target)? onOpenSettings;
  final VoidCallback? onOpenBackup;

  @override
  Widget build(BuildContext context) {
    final id = item.id;
    return Container(
      key: Key('whatsNewItem-$id'),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              key: Key('whatsNewItemHead-$id'),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                          child: Text(
                            '$number',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.tintInk),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.origin,
                              key: Key('whatsNewItemTag-$id'),
                              style: TextStyle(fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w700, color: palette.primary),
                            ),
                            Text(
                              item.title,
                              key: Key('whatsNewItemTitle-$id'),
                              style: TextStyle(fontSize: 14.5, height: 1.3, fontWeight: FontWeight.w800, color: palette.ink),
                            ),
                            if (!open)
                              Text(
                                item.summary,
                                key: Key('whatsNewItemSummary-$id'),
                                style: TextStyle(fontSize: 12.5, height: 1.35, color: palette.mutedInk),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ExcludeSemantics(
                        child: Icon(
                          open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 22,
                          color: open ? palette.primary : palette.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open) _details(),
        ],
      ),
    );
  }

  Widget _details() {
    final id = item.id;
    final body = TextStyle(fontSize: 13, height: 1.5, color: palette.softInk);
    final strong = TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w700, color: palette.ink);
    return Padding(
      key: Key('whatsNewItemBody-$id'),
      padding: const EdgeInsets.fromLTRB(54, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < item.paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(item.paragraphs[i], key: Key('whatsNewPara-$id-$i'), style: i == 0 && item.boldFirst ? strong : body),
          ],
          if (item.settingsTarget != null)
            _button(
              const Key('whatsNewCalSettings'),
              kWhatsNewOpenInSettings,
              onOpenSettings == null ? null : () => onOpenSettings!(item.settingsTarget),
            ),
          for (final l in item.extraLinks) _button(l.key, l.label, onOpenSettings == null ? null : () => onOpenSettings!(l.target)),
          if (item.backupButton) _button(const Key('whatsNewOpenBackup'), kWhatsNewOpenBackup, onOpenBackup),
        ],
      ),
    );
  }

  /// R13 (F4): a real button (a filled tint, 44 high), not an underlined link.
  /// Weeks and Backups use the same one. It is spoken as a button.
  Widget _button(Key key, String label, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.tonal(
        key: key,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          backgroundColor: palette.tint,
          foregroundColor: palette.tintInk,
          // F8 (R56): a 1 px primary border so the button shape reads (3:1+ vs the page in all 6 themes).
          side: BorderSide(color: palette.primary),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}
