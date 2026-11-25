/// §AUTOREAD.LEVELS.PERSON_ROW: one person or account on the second tab (layout A, 0.2.2 U5): name, a
/// detail line (kind, masked number, categories), the level line (the Auto-record ceiling, "Paused: asking
/// first", "Ask first is the highest level here") and the level pill that opens the level sheet. The pill
/// is dashed while Auto-record is paused (the line under the name says it in words too).
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
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

/// Readable name of a receiver kind (the row's detail line and the search).
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

  /// Category names for the detail line (rule category, or most-used ones).
  final List<String> categoryNames;

  /// The stored Auto-record ceiling in cents (0.2.2); null = none.
  final int? ceilingCents;

  /// Restored from a backup at Auto-record and on Ask first until reviewed (0.2.2, the rule's mark).
  final bool autoPending;
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
  });

  /// `type.key`, the row's id.
  String get id => '${type.code}.$key';

  /// The masked number shown on the row (Send Money only; other keys are not phone numbers).
  String? get maskedNumber => phoneEnding(type, key) == null ? null : maskPhone(key);
}

/// The level the row's pill names: an Auto-record person is asked first while paused.
RuleLevel shownLevel(LevelPerson x, {required bool paused}) =>
    x.level == RuleLevel.autoRecord && paused ? RuleLevel.askFirst : x.level;

/// The level line under the detail line, or null. [hard] = the Auto-record screens are on (autoRecordUi).
String? levelRowLine(LevelPerson x, {required bool paused, required bool hard}) {
  if (x.level == RuleLevel.autoRecord) {
    if (paused) return kHardRowPaused;
    final c = x.ceilingCents;
    return c == null ? kHardRowAutoNoCeiling : hardRowAutoCeiling(c);
  }
  if (hard && x.level == RuleLevel.askFirst && !canHoldAutoRecord(x.type)) return kHardRowAskFirstHighest;
  return null;
}

/// The detail line: kind, masked number, categories (or "No history yet").
String levelRowDetail(LevelPerson x) => [
      receiverKindName(x.type),
      if (x.maskedNumber != null) x.maskedNumber!,
      x.categoryNames.isEmpty ? kLevelsNoHistory : x.categoryNames.join(', '),
    ].join(' · ');

class LevelsPersonRow extends StatelessWidget {
  const LevelsPersonRow({super.key, required this.person, required this.onLevelTap, this.paused = false, this.hard = false});
  final LevelPerson person;
  final VoidCallback onLevelTap;

  /// "Pause all Auto-record" is on (only read while [hard]).
  final bool paused;

  /// The Auto-record screens are on (autoRecordUi).
  final bool hard;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isPaused = hard && paused && person.level == RuleLevel.autoRecord;
    final level = shownLevel(person, paused: isPaused);
    final tag = hardRuleLevelName(level);
    final ending = phoneEnding(person.type, person.key);
    final line = levelRowLine(person, paused: isPaused, hard: hard);
    final Color edge = switch (level) {
      RuleLevel.autoRecord => p.typeAirtime,
      RuleLevel.askFirst => p.primary,
      RuleLevel.suggested => p.line,
    };
    final Color fill = level == RuleLevel.suggested || isPaused ? Colors.transparent : p.tint;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(person.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 2),
            Text(levelRowDetail(person), key: const Key('levelRowDetail'), style: TextStyle(fontSize: 12.5, height: 1.35, color: p.mutedInk)),
            if (line != null)
              Text(line, key: const Key('levelRowLine'), style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: p.softInk)),
          ]),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: levelButtonSpoken(ending == null ? person.name : '${person.name}, number ending $ending', tag),
          excludeSemantics: true,
          onTap: onLevelTap,
          child: InkWell(
            key: Key('levelButton.${person.type.code}.${person.key}'),
            borderRadius: BorderRadius.circular(999),
            onTap: onLevelTap,
            child: CustomPaint(
              key: isPaused ? const Key('levelPillPaused') : null,
              painter: isPaused ? _DashedStadium(p.sun) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
                decoration: BoxDecoration(
                  color: fill,
                  border: isPaused ? null : Border.all(color: edge, width: 1.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tag,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: level == RuleLevel.autoRecord ? p.typeAirtime : p.ink)),
                  Icon(Icons.arrow_drop_down, size: 22, color: p.mutedInk),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The paused pill's dashed outline (amber).
class _DashedStadium extends CustomPainter {
  _DashedStadium(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)).deflate(0.75);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final PathMetric m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadium old) => old.color != color;
}
