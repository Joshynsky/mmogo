import 'package:flutter/material.dart';

import '../copy/privacy_copy.dart';
import '../copy/whats_new_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';

/// §UI.WHATSNEW.CARDS — the five cards of the What's-new pager (0.1.2 S11a,
/// WN1). One card at a time: its title (the focus target when the card
/// changes), the text, and the card's own extras (the picture, a link button,
/// the sign-off). The pager owns the buttons and the page position.
class WhatsNewCardView extends StatelessWidget {
  const WhatsNewCardView({
    super.key,
    required this.index,
    required this.palette,
    required this.titleFocus,
    this.onOpenSettings,
    this.onOpenBackup,
  });

  /// 0..4.
  final int index;
  final AppPalette palette;
  final FocusNode titleFocus;

  /// "Change in Settings" (card 2) and "Open Backup and restore" (card 4):
  /// injected, they push the route OVER the pager and mark nothing seen.
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenBackup;

  static const _titles = [
    kWhatsNewCard1Title,
    kWhatsNewCard2Title,
    kWhatsNewCard3Title,
    kWhatsNewCard4Title,
    kWhatsNewCard5Title,
  ];
  static const _bodies = [
    kWhatsNewCard1Body,
    kWhatsNewCard2Body,
    kWhatsNewCard3Body,
    kWhatsNewCard4Body,
    kWhatsNewCard5Body,
  ];

  /// The card's title text, for tests and for callers that need it.
  static String titleOf(int index) => _titles[index];

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 14, height: 1.45, color: palette.ink);
    return Column(
      key: Key('whatsNewCard$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          key: const Key('whatsNewCardTitleFocus'),
          focusNode: titleFocus,
          child: Semantics(
            header: true,
            child: Text(
              _titles[index],
              key: const Key('whatsNewCardTitle'),
              style: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: palette.ink),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(_bodies[index], key: const Key('whatsNewCardBody'), style: body),
        if (index == 0) ...[
          const SizedBox(height: 10),
          Text(
            kIndependenceShort,
            key: const Key('whatsNewIndependence'),
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
          ),
        ],
        if (index == 1) _button(const Key('whatsNewCalSettings'), kWhatsNewChangeInSettings, onOpenSettings),
        if (index == 2) ...[
          const SizedBox(height: 10),
          WhatsNewPicture(palette: palette),
          const SizedBox(height: 10),
          Text(kWhatsNewCard3Extra, key: const Key('whatsNewCard3Extra'), style: body),
        ],
        if (index == 3) _button(const Key('whatsNewOpenBackup'), kWhatsNewOpenBackup, onOpenBackup),
        if (index == 4) ...[
          const SizedBox(height: 10),
          Text(
            kWhatsNewSignOff,
            key: const Key('whatsNewSignOff'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
          ),
        ],
      ],
    );
  }

  /// R13 (F4): a real button (a filled tint, 44 high), not an underlined link.
  /// Cards 2 and 4 use the same one. It is spoken as a button.
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
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}

/// Card 3's picture: two numbers written two ways become one person. Invented
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
