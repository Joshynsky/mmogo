/// §AUTOREAD.LEVELS.PERSON_ROW: one person or account on the second tab (0.2.2 item 2 redesign, mock
/// mock-remembered-v2 page-open / page-auto / page-paused, rows style B): the name, an identity line (masked
/// number, then the payment type) and a line saying what mmogo does ("Suggests ...", "Suggests from last
/// 10 payments", "Asks: Record as ...?", "Records as ..., up to Ksh ...", "Paused: asking first"). The
/// whole row is one button with a chevron; it opens the person's sheet. No level pill: the group header
/// names the level. While Auto-record is paused the row says so in words, and the spoken label says
/// "Auto-record" and "paused" (never "Ask first").
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/tap_target.dart' show kMinTapTarget;
import '../../logic/phone_mask.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'levels_copy.dart';

/// Send Money people are keyed by phone number. Two numbers can share one name
/// (the same person on two phones), so the row ends with the last 3 digits.
String? phoneEnding(ReceiverType type, String key) {
  if (type != ReceiverType.sendMoney) return null;
  final digits = key.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6) return null;
  return digits.substring(digits.length - 3);
}

/// Readable name of a receiver kind (the row's identity line and the search).
String receiverKindName(ReceiverType t) => switch (t) {
      ReceiverType.sendMoney => kSpokenSendMoney,
      ReceiverType.payBill => kSpokenPayBill,
      ReceiverType.buyGoods => kSpokenBuyGoods,
      ReceiverType.pochi => kSpokenPochi,
    };

/// What a row shows; built by the tab from rules, known names and history.
class LevelPerson {
  final ReceiverType type;
  final String key;
  final String name;
  final RuleLevel level;
  final int? categoryId;

  /// Most-used category ids (up to 2) from history, for the sheet's suggestions.
  final List<int> topIds;

  /// Category names (rule category, or most-used ones; the search and the sheet read them).
  final List<String> categoryNames;

  /// The stored Auto-record ceiling in cents (0.2.2); null = none.
  final int? ceilingCents;

  /// Restored from a backup at Auto-record and on Ask first until reviewed (0.2.2, the rule's mark).
  final bool autoPending;

  /// The Suggest categories the person chose (0.2.2 redesign, the rule's `chosenCategoryIds`; Suggested
  /// only). Empty = "Last 10 payments".
  final List<int> chosenCategoryIds;

  /// The names of [chosenCategoryIds] that still exist, in the chosen order (the row's "Suggests ..." line).
  final List<String> chosenCategoryNames;

  const LevelPerson({
    required this.type,
    required this.key,
    required this.name,
    required this.level,
    this.categoryId,
    this.topIds = const [],
    this.categoryNames = const [],
    this.ceilingCents,
    this.autoPending = false,
    this.chosenCategoryIds = const [],
    this.chosenCategoryNames = const [],
  });

  /// `type.key`, the row's id.
  String get id => '${type.code}.$key';

  /// The masked number shown on the row (Send Money only; other keys are not phone numbers).
  String? get maskedNumber => phoneEnding(type, key) == null ? null : maskPhone(key);

  /// This person with the chosen Suggest list of [r] (only while [level] is Suggested; [cats] = id -> name;
  /// a deleted category is left out of the names).
  LevelPerson withChosenFrom(ReceiverRule? r, Map<int, String> cats) {
    final ids = level == RuleLevel.suggested && r != null ? r.chosenCategoryIds : const <int>[];
    if (ids.isEmpty && chosenCategoryIds.isEmpty) return this;
    return LevelPerson(
      type: type,
      key: key,
      name: name,
      level: level,
      categoryId: categoryId,
      topIds: topIds,
      categoryNames: categoryNames,
      ceilingCents: ceilingCents,
      autoPending: autoPending,
      chosenCategoryIds: List.unmodifiable(ids),
      chosenCategoryNames: List.unmodifiable([for (final i in ids) if (cats[i] != null) cats[i]!]),
    );
  }
}

/// The line saying what mmogo does for [x] (mock rows). [paused] = "Pause all Auto-record" is on and the
/// Auto-record screens are on. A category that no longer exists reads "No category yet".
String levelRowLine(LevelPerson x, {required bool paused}) {
  final cat = x.categoryNames.isEmpty ? null : x.categoryNames.first;
  switch (x.level) {
    case RuleLevel.suggested:
      return x.chosenCategoryNames.isEmpty ? kHardSuggestsFromLast10 : hardRowSuggests(x.chosenCategoryNames.join(', '));
    case RuleLevel.askFirst:
      return cat == null ? kHardNoCategoryYet : hardRowAsks(cat);
    case RuleLevel.autoRecord:
      if (paused) return kHardRowPaused;
      if (cat == null) return kHardNoCategoryYet;
      final c = x.ceilingCents;
      return c == null ? hardRowRecordsNoLimit(cat) : hardRowRecordsUpTo(cat, c);
  }
}

/// The identity line (mock rows style B): the masked number (Send Money), then the payment type.
String levelRowDetail(LevelPerson x) => [
      if (x.maskedNumber != null) x.maskedNumber!,
      receiverKindName(x.type),
    ].join(' · ');

/// What a screen reader says for the row: who (name, type, number ending), the level, and the row's line.
/// A paused Auto-record person is announced as "Auto-record" with the paused line (B-review a11y).
String levelRowSpoken(LevelPerson x, {required bool paused}) {
  final ending = phoneEnding(x.type, x.key);
  final who = [x.name, receiverKindName(x.type), if (ending != null) 'number ending $ending'].join(', ');
  return levelButtonSpoken(who, '${hardRuleLevelName(x.level)}, ${levelRowLine(x, paused: paused)}');
}

class LevelsPersonRow extends StatelessWidget {
  const LevelsPersonRow({super.key, required this.person, required this.onLevelTap, this.paused = false, this.hard = false});
  final LevelPerson person;

  /// The row's tap: opens the person's sheet.
  final VoidCallback onLevelTap;

  /// "Pause all Auto-record" is on (only read while [hard]).
  final bool paused;

  /// The Auto-record screens are on (autoRecordUi).
  final bool hard;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isPaused = hard && paused && person.level == RuleLevel.autoRecord;
    return Semantics(
      button: true,
      label: levelRowSpoken(person, paused: isPaused),
      excludeSemantics: true,
      onTap: onLevelTap,
      child: InkWell(
        key: Key('levelButton.${person.type.code}.${person.key}'),
        onTap: onLevelTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 12),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(person.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(height: 2),
                Text(levelRowDetail(person),
                    key: const Key('levelRowDetail'), style: TextStyle(fontSize: 12.5, height: 1.35, color: p.mutedInk)),
                Text(levelRowLine(person, paused: isPaused),
                    key: isPaused ? const Key('levelRowPaused') : const Key('levelRowLine'),
                    style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w700, color: p.softInk)),
              ]),
            ),
            const SizedBox(width: 4),
            // chevron_right follows the text direction (it points left in RTL).
            Icon(Icons.chevron_right, size: 22, color: p.mutedInk),
          ]),
        ),
      ),
    );
  }
}
