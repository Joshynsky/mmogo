/// §AUTOREAD.LEVELS.HARD_RULE_SLOTS: fills the Remembered page's second-tab slots ([LevelsSlots], U5)
/// with the 0.2.2 page controls (I1): the pause card (U4) under the helper line, the paused banner (U4)
/// and the restore review line (U6) first in the list, the red "Reset everyone to Suggested" footer (U4)
/// pinned at the bottom. All share the deps' ONE pause port and the page's store. While [autoRecordUi] is false
/// no slot is filled (the tab is exactly the 0.2.1 one). A control that draws nothing leaves no gap.
library;

import 'package:flutter/material.dart';

import '../../../ui/widgets/collapsing_padding.dart';
import 'hard_rule_pause_card.dart';
import 'hard_rule_paused_banner.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'hard_rule_reset_footer.dart';
import 'levels_deps.dart';
import 'levels_tab.dart' show LevelsSlots;
import 'review_line.dart';

/// The slots for [d]. Empty while the Auto-record screens are off or there are no deps. The pause card
/// and the banner need a pause port (none = not drawn). The review line is drawn by the tab only while
/// "Record receiver details" is on, so it is built with details on.
LevelsSlots hardRuleSlotsFor(LevelsDeps? d) {
  if (!autoRecordUi || d == null) return const LevelsSlots();
  final pause = d.pause;
  final bulk = d.bulk;
  return LevelsSlots(
    pauseCard: pause == null
        ? null
        : (_) => CollapsingPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: HardRulePauseCard(key: const Key('slotPauseCard'), port: pause, bulk: bulk)),
    pausedBanner: pause == null
        ? null
        : (_) => CollapsingPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: HardRulePausedBanner(key: const Key('slotPausedBanner'), port: pause, bulk: bulk)),
    reviewLine: (_) => CollapsingPadding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: ReviewLine(key: const Key('slotReviewLine'), bulk: bulk, now: d.now)),
    resetFooter: (_) => SafeArea(
        top: false,
        child: CollapsingPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: HardRuleResetFooter(key: const Key('slotResetFooter'), bulk: bulk))),
  );
}
