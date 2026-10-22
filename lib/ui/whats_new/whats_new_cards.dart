import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/ui/whats_new_autoread_copy.dart';
import '../copy/whats_new_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';

/// §UI.WHATSNEW.CARDS — the items of the What's-new page (0.1.2 A5a; they were
/// the six cards of the pager). A hook file (see `kAutoReadHookFiles`): the
/// auto-read build's banner, intro and items are reached only inside
/// `if (kAutoReadCompiled)`, so the standard build drops them.
///
/// One item = a closed row (number, title, one-line summary) that opens to its
/// full text. The page owns which rows are open.

/// What one item says. [paragraphs] come first; [picture] and [afterPicture]
/// (item 3), the two route buttons and the privacy emphasis are item extras.
class WhatsNewItem {
  const WhatsNewItem({
    required this.id,
    required this.title,
    required this.summary,
    this.paragraphs = const [],
    this.picture = false,
    this.afterPicture,
    this.settingsButton = false,
    this.backupButton = false,
    this.boldFirst = false,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> paragraphs;
  final bool picture;
  final String? afterPicture;
  final bool settingsButton;
  final bool backupButton;

  /// The first paragraph is the signed Privacy sentence: shown in the ink colour, bold.
  final bool boldFirst;
}

/// The page's items for this build: six in the standard build; the auto-read
/// build adds its own item first and says its own words in Notifications and
/// Privacy.
List<WhatsNewItem> whatsNewItems() => [
  if (kAutoReadCompiled)
    WhatsNewItem(
      id: 'reading',
      title: kWhatsNewReadingTitle,
      summary: kWhatsNewReadingSummary,
      paragraphs: [kWhatsNewReadingBody, kWhatsNewReadingBody2],
    ),
  const WhatsNewItem(
    id: 'withdrawals',
    title: kWhatsNewCard1Title,
    summary: kWhatsNewCard1Summary,
    paragraphs: [kWhatsNewCard1Body, kWhatsNewCard1Body2],
  ),
  const WhatsNewItem(
    id: 'weeks',
    title: kWhatsNewCard2Title,
    summary: kWhatsNewCard2Summary,
    paragraphs: [kWhatsNewCard2Body],
    settingsButton: true,
  ),
  const WhatsNewItem(
    id: 'phone',
    title: kWhatsNewCard3Title,
    summary: kWhatsNewCard3Summary,
    paragraphs: [kWhatsNewCard3Body],
    picture: true,
    afterPicture: kWhatsNewCard3Extra,
  ),
  const WhatsNewItem(
    id: 'backups',
    title: kWhatsNewCard4Title,
    summary: kWhatsNewCard4Summary,
    paragraphs: [kWhatsNewCard4Body],
    backupButton: true,
  ),
  if (kAutoReadCompiled)
    const WhatsNewItem(
      id: 'notifications',
      title: kWhatsNewCardNotificationsTitle,
      summary: kWhatsNewAutoNotificationsSummary,
      paragraphs: [kWhatsNewAutoNotificationsBody],
    )
  else
    const WhatsNewItem(
      id: 'notifications',
      title: kWhatsNewCardNotificationsTitle,
      summary: kWhatsNewCardNotificationsSummary,
      paragraphs: [kWhatsNewCardNotificationsBody],
    ),
  if (kAutoReadCompiled)
    const WhatsNewItem(
      id: 'privacy',
      title: kWhatsNewCard5Title,
      summary: kWhatsNewPrivacyAutoReadSummaryProvisional,
      paragraphs: [kWhatsNewPrivacyAutoReadBodyProvisional],
      boldFirst: true,
    )
  else
    WhatsNewItem(
      id: 'privacy',
      title: kWhatsNewCard5Title,
      summary: kWhatsNewCard5Summary,
      paragraphs: [kWhatsNewCard5Body, kWhatsNewCard5Network],
      boldFirst: true,
    ),
];

/// The line under the title for this build.
String whatsNewIntro() => kAutoReadCompiled ? kWhatsNewAutoIntro : kWhatsNewIntro;

/// The banner at the very top: a tinted note saying which version this is.
/// The standard build's banner has the link to the mmogo page; the auto-read
/// build's has none.
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
          if (kAutoReadCompiled)
            const SizedBox(height: 10)
          else
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
                child: const Text(
                  kWhatsNewBannerLink,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
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
  final VoidCallback? onOpenSettings;
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
          if (item.picture) ...[const SizedBox(height: 10), WhatsNewPicture(palette: palette)],
          if (item.afterPicture != null) ...[
            const SizedBox(height: 10),
            Text(item.afterPicture!, key: const Key('whatsNewCard3Extra'), style: body),
          ],
          if (item.settingsButton)
            _button(const Key('whatsNewCalSettings'), kWhatsNewChangeInSettings, onOpenSettings),
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

/// Item 3's picture: two numbers written two ways become one person. Invented
/// name and amounts (from the mock). One semantics label describes it all.
class WhatsNewPicture extends StatelessWidget {
  const WhatsNewPicture({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: 12.5, color: palette.ink);
    final bold = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: palette.ink);
    Widget head(String t) => Text(
      t.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: palette.mutedInk),
    );
    Widget row(String name, String amount, {bool strong = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(name, style: strong ? bold : small)),
        const SizedBox(width: 8),
        Text(amount, style: bold),
      ],
    );
    return Semantics(
      container: true,
      label: kWhatsNewPicLabel,
      image: true,
      excludeSemantics: true,
      child: Container(
        key: const Key('whatsNewPicture'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head(kWhatsNewPicBefore),
            const SizedBox(height: 4),
            row('0712 345 678', 'Ksh 1,200'),
            const SizedBox(height: 4),
            row('+254 712 345 678', 'Ksh 300'),
            const SizedBox(height: 4),
            Center(
              child: Text(kWhatsNewPicBecomes, style: TextStyle(fontWeight: FontWeight.w800, color: palette.mutedInk)),
            ),
            const SizedBox(height: 4),
            head(kWhatsNewPicNow),
            const SizedBox(height: 4),
            row('Jane Sample', 'Ksh 1,500', strong: true),
          ],
        ),
      ),
    );
  }
}
