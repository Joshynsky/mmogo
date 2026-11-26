/// §AUTOREAD.LEVELS.PERSON_SHEET_PARTS: the drawn pieces of the 0.2.2 person sheet (item 2 redesign, slice
/// U-PERSON; mock-remembered-v2 p-*): the header (back arrow, name, masked number, "{k} payments"), the three
/// level buttons, the "How ... works" box, the Paybill line, the category line and the category button.
/// Stateless; the sheet (person_sheet.dart) holds the state. Words only from hard_rule_copy.dart.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'person_sheet_rules.dart';

/// True when the text is scaled past [kPersonSheetStackScale] (rows stack instead).
bool personSheetStacked(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10 > kPersonSheetStackScale;

/// Back arrow at the start, the name (heading), the masked number at the end; "{k} payments" under it.
/// No close X (mock p-*).
class PersonSheetHeader extends StatelessWidget {
  const PersonSheetHeader({super.key, required this.name, this.maskedNumber, this.paymentCount, required this.onBack});
  final String name;
  final String? maskedNumber;
  final int? paymentCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mask = maskedNumber;
    final count = paymentCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('personBack'),
              tooltip: kHardBack,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.arrow_back, color: p.ink),
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  name,
                  key: const Key('levelSheetTitle'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink),
                ),
              ),
            ),
            if (mask != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  mask,
                  key: const Key('personMask'),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13.5, color: p.softInk),
                ),
              ),
            ],
          ],
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
            child: Text(
              hardPaymentsCount(count),
              key: const Key('personCount'),
              style: TextStyle(fontSize: 13.5, color: p.softInk),
            ),
          ),
      ],
    );
  }
}

/// "Set to" and the three level buttons (mock p-* `.seg`): a radio group; the chosen one is filled and
/// carries a check mark (not colour only). [autoAllowed] false = Auto-record greyed, said "disabled" to a
/// screen reader with the Paybill reason, and taps on it do nothing. Stacked above 150% text.
class PersonLevelChoice extends StatelessWidget {
  const PersonLevelChoice({super.key, required this.selected, required this.autoAllowed, this.onPick});
  final RuleLevel selected;
  final bool autoAllowed;

  /// Null while saving (every button inert).
  final ValueChanged<RuleLevel>? onPick;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final stacked = personSheetStacked(context);
    final buttons = [
      for (final l in RuleLevel.values)
        _LevelButton(
          key: Key('levelChoice${l.name}'),
          level: l,
          on: selected == l,
          enabled: l != RuleLevel.autoRecord || autoAllowed,
          onTap: onPick == null ? null : () => onPick!(l),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            kHardSetTo,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.softInk),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          container: true,
          label: kHardSetTo,
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final b in buttons) ...[if (b != buttons.first) const SizedBox(height: 8), b],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final b in buttons) ...[if (b != buttons.first) const SizedBox(width: 8), Expanded(child: b)],
                  ],
                ),
        ),
      ],
    );
  }
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({super.key, required this.level, required this.on, required this.enabled, this.onTap});
  final RuleLevel level;
  final bool on;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final words = personSheetLevelButton(level);
    final tap = enabled ? onTap : null;
    final ink = !enabled ? p.mutedInk : (on ? p.onPrimary : p.ink);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      enabled: enabled,
      button: true,
      label: enabled ? words : '$words. $kHardPaybillAlwaysAsks',
      excludeSemantics: true,
      onTap: tap,
      child: Material(
        color: on ? p.primary : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? p.primary : p.line, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: Alignment.center,
            child: Text.rich(
              TextSpan(
                children: [
                  if (on) const TextSpan(text: '✓ '),
                  TextSpan(text: words),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ink,
                // Greyed: the Paybill line under the buttons is the non-colour cue.
                fontStyle: enabled ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tinted box with a bold heading and a paragraph (mock `.para`): the level's "How ... works" and the
/// limit's "What Ask first above means".
class PersonHowBox extends StatelessWidget {
  const PersonHowBox({super.key, required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.tintInk),
            ),
          ),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.tintInk)),
        ],
      ),
    );
  }
}

/// "Paybill payments always ask first." with an amber bar at the start edge (mock p-paybill `.why`).
class PersonPaybillLine extends StatelessWidget {
  const PersonPaybillLine({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: const Key('personPaybillLine'),
      padding: const EdgeInsetsDirectional.only(start: 10, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: p.sun, width: 3)),
      ),
      child: Text(kHardPaybillAlwaysAsks, style: TextStyle(fontSize: 13.5, height: 1.35, color: p.softInk)),
    );
  }
}

/// Under a category: the hint line ([hint]) or, after a Save with no category, the error line (announced).
class PersonCategoryNote extends StatelessWidget {
  const PersonCategoryNote({super.key, this.hint, this.error = false});
  final String? hint;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (error) {
      return Semantics(
        liveRegion: true,
        child: Text(
          kHardCategoryError,
          key: const Key('levelCategoryError'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.error),
        ),
      );
    }
    final h = hint;
    if (h == null) return const SizedBox.shrink();
    return Text(
      h,
      key: const Key('levelCategoryHint'),
      style: TextStyle(fontSize: 12.5, height: 1.35, color: p.softInk),
    );
  }
}

/// Ask first's "Category: {name}" line (mock p-ask `.cur`); "No category yet" when none.
class PersonCategoryLine extends StatelessWidget {
  const PersonCategoryLine({super.key, required this.category});
  final String? category;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final c = category;
    return Text.rich(
      key: const Key('levelCategoryLine'),
      TextSpan(
        children: [
          TextSpan(
            text: '$kHardCategoryLabel: ',
            style: TextStyle(fontSize: 13, color: p.softInk),
          ),
          TextSpan(
            text: c ?? kHardNoCategoryYet,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink),
          ),
        ],
      ),
    );
  }
}

/// Auto-record's "Choose category" row: the label and a button showing the category (mock p-auto `.frow`).
/// Stacked above 150% text. [bad] = the error border after a Save with no category.
class PersonCategoryButton extends StatelessWidget {
  const PersonCategoryButton({super.key, required this.category, required this.onTap, this.bad = false});
  final String? category;
  final VoidCallback? onTap;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final c = category ?? kHardNoCategoryYet;
    final label = ExcludeSemantics(
      child: Text(
        kHardCategoryChoose,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink),
      ),
    );
    final button = Semantics(
      button: true,
      label: kHardCategoryChoose,
      value: c,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: bad ? p.error : p.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('levelCategoryRow'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c,
                    key: const Key('levelCategoryValue'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: category == null ? p.mutedInk : p.ink,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 24, color: p.mutedInk),
              ],
            ),
          ),
        ),
      ),
    );
    if (personSheetStacked(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [label, const SizedBox(height: 6), button],
      );
    }
    return Row(
      children: [
        Expanded(flex: 2, child: label),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: button),
      ],
    );
  }
}
