import 'package:flutter/material.dart';

import '../../autoread/autoread_feature.dart';
import '../../autoread/ui/whats_new_autoread_copy.dart';
import '../copy/data_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../screens/settings/settings_targets.dart';

/// §UI.WHATSNEW.ITEMS — the items of the What's-new page and what each says (0.2.2: split out of
/// `whats_new_cards.dart`). A hook file (see `kAutoReadHookFiles`): the auto-read build's items
/// and lines are reached only inside `if (kAutoReadCompiled)`, so the standard build drops them.

/// A second "open this Settings area" button on an item (0.2.1 #10): its [target] id, its [label] and its [key].
class WhatsNewLink {
  const WhatsNewLink({required this.target, required this.label, required this.key});

  final String target;
  final String label;
  final Key key;
}

/// What one item says. [paragraphs] come first; the two route buttons and the
/// privacy emphasis are item extras.
class WhatsNewItem {
  const WhatsNewItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.origin,
    this.paragraphs = const [],
    this.settingsTarget,
    this.extraLinks = const [],
    this.backupButton = false,
    this.boldFirst = false,
    this.group = WhatsNewGroup.headline,
  });

  final String id;
  final String title;
  final String summary;

  /// The tag line: [kWhatsNewTagNew].
  final String origin;
  final List<String> paragraphs;

  /// The Settings area the "Open in Settings" button opens and outlines (null: no button).
  final String? settingsTarget;

  /// More Settings buttons, after the first one.
  final List<WhatsNewLink> extraLinks;
  final bool backupButton;

  /// The first paragraph is the signed Privacy sentence: shown in the ink colour, bold.
  final bool boldFirst;

  /// Where the page puts the item: always shown, in the "More changes" fold, or last (Privacy).
  final WhatsNewGroup group;
}

/// The three places an item can sit on the page.
enum WhatsNewGroup { headline, more, last }

/// A "More changes" row: its own words only, one paragraph, no button.
WhatsNewItem _more(String id, String title, String summary, List<String> paragraphs) =>
    WhatsNewItem(id: id, origin: kWhatsNewTagNew, title: title, summary: summary, paragraphs: paragraphs, group: WhatsNewGroup.more);

/// The page's items for this build (PM-signed draft, 26-11-2026; order changed by the PM 27-11-2026: Auto-record items first, then search, regroup, black, backups, ocean; the five
/// shared items, then (auto-read only) the four Auto-record items, the "More changes" fold, and
/// Privacy last.
List<WhatsNewItem> whatsNewItems() => [
  if (kAutoReadCompiled) ...const [
    WhatsNewItem(
      id: 'autorecord',
      origin: kWhatsNewTagNew,
      title: kWhatsNewAutoRecordTitle,
      summary: kWhatsNewAutoRecordSummary,
      paragraphs: kWhatsNewAutoRecordBody,
      settingsTarget: kSettingsTargetRemembered,
    ),
    WhatsNewItem(
      id: 'pause',
      origin: kWhatsNewTagNew,
      title: kWhatsNewPauseTitle,
      summary: kWhatsNewPauseSummary,
      paragraphs: [kWhatsNewPauseBody],
    ),
    WhatsNewItem(
      id: 'suggest',
      origin: kWhatsNewTagNew,
      title: kWhatsNewSuggestTitle,
      summary: kWhatsNewSuggestSummary,
      paragraphs: [kWhatsNewSuggestBody],
    ),
    WhatsNewItem(
      id: 'reset',
      origin: kWhatsNewTagNew,
      title: kWhatsNewResetTitle,
      summary: kWhatsNewResetSummary,
      paragraphs: [kWhatsNewResetBody],
    ),
  ],
  const WhatsNewItem(
    id: 'search',
    origin: kWhatsNewTagNew,
    title: kWhatsNewSearchTitle,
    summary: kWhatsNewSearchSummary,
    paragraphs: [kWhatsNewSearchBody],
  ),
  const WhatsNewItem(
    id: 'regroup',
    origin: kWhatsNewTagNew,
    title: kWhatsNewRegroupTitle,
    summary: kWhatsNewRegroupSummary,
    paragraphs: [kAutoReadCompiled ? kWhatsNewAutoRegroupBody : kWhatsNewRegroupBody],
  ),
  const WhatsNewItem(
    id: 'black',
    origin: kWhatsNewTagNew,
    title: kWhatsNewBlackTitle,
    summary: kWhatsNewBlackSummary,
    paragraphs: [kWhatsNewBlackBody],
  ),
  if (kAutoReadCompiled)
    const WhatsNewItem(
      id: 'backups',
      origin: kWhatsNewTagNew,
      title: kWhatsNewAutoBackupsTitle,
      summary: kWhatsNewAutoBackupsSummary,
      paragraphs: ['$kWhatsNewAutoBackupsIntro $kWhatsNewAutoBackupsOlder $kBackupNotRestorableByOlderV6', kWhatsNewAutoBackupsKeepIt],
    )
  else
    const WhatsNewItem(
      id: 'backups',
      origin: kWhatsNewTagNew,
      title: kWhatsNewBackupsTitle,
      summary: kWhatsNewBackupsSummary,
      paragraphs: [kWhatsNewBackupsBody],
    ),
  const WhatsNewItem(
    id: 'ocean',
    origin: kWhatsNewTagNew,
    title: kWhatsNewOceanTitle,
    summary: kWhatsNewOceanSummary,
    paragraphs: [kWhatsNewOceanBody],
  ),
  // More changes (fold).
  _more('home', kWhatsNewHomeTitle, kWhatsNewHomeSummary, [kWhatsNewHomeBody]),
  _more('samename', kWhatsNewSameNameTitle, kWhatsNewSameNameBody, [kWhatsNewSameNameBody]),
  _more('notnow', kWhatsNewNotNowTitle, kWhatsNewNotNowBody, [kWhatsNewNotNowBody]),
  _more('receiver', kWhatsNewReceiverTitle, kWhatsNewReceiverBody, [kWhatsNewReceiverBody]),
  if (kAutoReadCompiled) ...[
    _more('todo', kWhatsNewTodoTitle, kWhatsNewTodoBody, [kWhatsNewTodoBody]),
    _more('fixes', kWhatsNewFixesTitle, kWhatsNewFixesSummary, [kWhatsNewFixesBody]),
  ],
  // Last.
  if (kAutoReadCompiled)
    const WhatsNewItem(
      id: 'privacy',
      origin: kWhatsNewTagNew,
      title: kWhatsNewCard5Title,
      summary: kWhatsNewPrivacyAutoReadSummary,
      paragraphs: [kWhatsNewPrivacyAutoReadBody, kWhatsNewPrivacyRules],
      boldFirst: true,
      group: WhatsNewGroup.last,
    )
  else
    const WhatsNewItem(
      id: 'privacy',
      origin: kWhatsNewTagNew,
      title: kWhatsNewCard5Title,
      summary: kWhatsNewCard5Summary,
      paragraphs: [kWhatsNewCard5Body, kWhatsNewPrivacyRules],
      boldFirst: true,
      group: WhatsNewGroup.last,
    ),
];

/// The line under the title for this build.
String whatsNewIntro() => kWhatsNewIntro;

/// The Updates entry's text for this build (the auto-read build adds its Auto-record line).
String whatsNewEntryBody() => kAutoReadCompiled ? '$kWhatsNewEntryBody $kWhatsNewAutoEntryExtra' : kWhatsNewEntryBody;
