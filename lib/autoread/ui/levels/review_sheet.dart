/// §AUTOREAD.LEVELS.REVIEW_SHEET: the restore review (0.2.2 item 2, slice U6, mock rst-review).
/// People restored from a backup at Auto-record come back on Ask first with the rule's `autoPending`
/// mark. This sheet lists them, each with a two-way choice Ask first (the default) / Auto-record.
/// Confirm puts the picked people back on Auto-record with the backup's category and ceiling (PM D4)
/// and the rest on Ask first; "Keep all on Ask first" puts everyone on Ask first; both clear the mark.
/// Closing the sheet changes nothing (they stay pending). Every write goes through RuleStore.setLevel:
/// nobody reaches Auto-record without an explicit pick.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/bottom_sheet_shell.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../../ui/widgets/tap_target.dart';
import '../../logic/phone_mask.dart';
import '../../rules/rule_model.dart';
import '../../rules/rule_store.dart';
import 'hard_rule_copy.dart';
import 'levels_copy.dart';

// ---------------------------------------------------------------- what the sheet returns

/// The sheet's answer. Null from [showReviewSheet] = closed, nothing changes.
class ReviewChoice {
  const ReviewChoice._(this.keepAll, this.autoIds);

  /// "Keep all on Ask first".
  const ReviewChoice.keepAll() : this._(true, const {});

  /// "Confirm" with the people picked for Auto-record ([reviewId]s).
  const ReviewChoice.confirm(Set<String> autoIds) : this._(false, autoIds);

  final bool keepAll;
  final Set<String> autoIds;
}

/// The id a person has in a [ReviewChoice].
String reviewId(ReceiverRule r) => '${r.type.code}.${r.key}';

/// Whether the sheet offers Auto-record for [r]: a kind that can hold it and a stored category.
bool reviewCanAuto(ReceiverRule r) => canHoldAutoRecord(r.type) && r.categoryId != null;

// ---------------------------------------------------------------- applying a choice

/// What [applyReview] did.
class ReviewApplied {
  const ReviewApplied({required this.auto, required this.askFirst, required this.failed});

  /// People now on Auto-record.
  final int auto;

  /// People now on Ask first (mark cleared).
  final int askFirst;

  /// Writes refused or failed (those people keep their mark and stay in the review).
  final int failed;
}

/// Applies [choice] to [people]. Each rule is read again first: someone who is no longer pending
/// (changed meanwhile, forgotten) is left alone. A picked person who can hold Auto-record goes to
/// Auto-record with the stored category and ceiling; everyone else to Ask first with the stored
/// category and ceiling. Only [RuleStore.setLevel] writes, and it clears the mark.
Future<ReviewApplied> applyReview(RuleStore store, List<ReceiverRule> people, ReviewChoice choice, DateTime at) async {
  var auto = 0, ask = 0, failed = 0;
  for (final p in people) {
    ReceiverRule? r;
    try {
      r = await store.get(p.type, p.key);
    } catch (_) {
      failed++;
      continue;
    }
    if (r == null || !r.autoPending) continue;
    final toAuto = !choice.keepAll && choice.autoIds.contains(reviewId(r)) && reviewCanAuto(r);
    final level = toAuto ? RuleLevel.autoRecord : RuleLevel.askFirst;
    var ok = false;
    try {
      ok = await store.setLevel(r.type, r.key,
          name: r.name, level: level, categoryId: r.categoryId, ceilingCents: r.ceilingCents, at: at);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      failed++;
    } else if (toAuto) {
      auto++;
    } else {
      ask++;
    }
  }
  return ReviewApplied(auto: auto, askFirst: ask, failed: failed);
}

/// The toast after [a]: a failure says so (the review line stays for another try); Auto-record
/// people are counted; otherwise everyone is on Ask first.
String reviewToastText(ReviewApplied a) {
  if (a.failed > 0) return kLevelSheetSaveFailed;
  if (a.auto > 0) return hardReviewToast(a.auto);
  return kHardReviewKeptToast;
}

/// Opens the sheet for [people], applies the answer through [store] and shows the toast. Returns
/// what was applied, or null when the sheet was closed (nothing changed).
Future<ReviewApplied?> reviewRestoredPeople(
  BuildContext context, {
  required RuleStore store,
  required List<ReceiverRule> people,
  DateTime Function() now = DateTime.now,
}) async {
  final choice = await showReviewSheet(context, people: people);
  if (choice == null) return null;
  final applied = await applyReview(store, people, choice, now());
  PillToast.show(reviewToastText(applied));
  return applied;
}

// ---------------------------------------------------------------- the sheet

/// The review sheet; resolves to the answer, or null when closed (Back, swipe, tap outside).
Future<ReviewChoice?> showReviewSheet(BuildContext context, {required List<ReceiverRule> people}) {
  return showModalBottomSheet<ReviewChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReviewSheet(people: people),
  );
}

class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, required this.people});
  final List<ReceiverRule> people;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  // Everyone starts on Ask first; only a tap adds a person here.
  final Set<String> _auto = {};

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return BottomSheetShell(
      key: const Key('reviewSheet'),
      palette: p,
      children: [
        Semantics(
          header: true,
          child: Text(
            kHardReviewTitle,
            key: const Key('reviewSheetTitle'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
          ),
        ),
        Text(kHardReviewSub, style: TextStyle(fontSize: 13, height: 1.4, color: p.softInk)),
        for (var i = 0; i < widget.people.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.line),
          ReviewPersonRow(
            key: Key('reviewRow${reviewId(widget.people[i])}'),
            rule: widget.people[i],
            auto: _auto.contains(reviewId(widget.people[i])),
            onPick: (auto) => setState(() {
              final id = reviewId(widget.people[i]);
              auto ? _auto.add(id) : _auto.remove(id);
            }),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('reviewKeepAll'),
                onPressed: () => Navigator.of(context).pop(const ReviewChoice.keepAll()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  foregroundColor: p.ink,
                  side: BorderSide(color: p.line, width: 1.5),
                ),
                child: const Text(kHardReviewKeepAll, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('reviewConfirm'),
                onPressed: () => Navigator.of(context).pop(ReviewChoice.confirm(Set.of(_auto))),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  backgroundColor: p.primary,
                  foregroundColor: p.onPrimary,
                ),
                child: const Text(kHardReviewConfirm, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The kind name a row shows under the person's name (the existing type names).
String reviewKindName(ReceiverType t) => switch (t) {
      ReceiverType.sendMoney => kSpokenSendMoney,
      ReceiverType.payBill => kSpokenPayBill,
      ReceiverType.buyGoods => kSpokenBuyGoods,
      ReceiverType.pochi => kSpokenPochi,
    };

/// One person: name, kind (and masked number for Send Money), then the two-way choice. When they do
/// not fit on one line the choice moves under the name so nothing clips.
class ReviewPersonRow extends StatelessWidget {
  const ReviewPersonRow({super.key, required this.rule, required this.auto, required this.onPick});
  final ReceiverRule rule;
  final bool auto;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final sub = rule.type == ReceiverType.sendMoney
        ? '${reviewKindName(rule.type)} · ${maskPhone(rule.key)}'
        : reviewKindName(rule.type);
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rule.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink)),
        Text(sub, style: TextStyle(fontSize: 12.5, color: p.softInk)),
      ],
    );
    final choice = Semantics(
      container: true,
      label: rule.name,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _Option(
            key: const Key('reviewPickAsk'),
            text: kHardLevelAskFirst,
            selected: !auto,
            onTap: () => onPick(false),
          ),
          _Option(
            key: const Key('reviewPickAuto'),
            text: kHardLevelAutoRecord,
            selected: auto,
            onTap: reviewCanAuto(rule) ? () => onPick(true) : null,
          ),
        ],
      ),
    );
    // Side by side when both fit (the choice at the end edge, RTL-safe); otherwise the choice wraps
    // under the name (large text, narrow screens), and the two options wrap too if they must.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [who, choice],
        ),
      ),
    );
  }
}

/// One half of the two-way choice: a 44 px pill; selected = filled AND marked checked (not colour
/// alone: the screen reader says "selected", and the filled shape differs from the outlined one).
class _Option extends StatelessWidget {
  const _Option({super.key, required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final enabled = onTap != null;
    final fg = selected ? p.onPrimary : (enabled ? p.ink : p.mutedInk);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget, minWidth: kMinTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? p.primary : Colors.transparent,
            border: Border.all(color: selected ? p.primary : p.line, width: 1.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
