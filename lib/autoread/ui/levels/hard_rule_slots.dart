/// §AUTOREAD.LEVELS.HARD_RULE_SLOTS: fills the Remembered page's second-tab slots ([LevelsSlots]) with the
/// 0.2.2 page controls (item 2 redesign): the pause switch row (U-CTRL, today's HardRulePauseCard) pinned
/// at the top, the restore review line (U6) first in the list, the bottom bar (U-CTRL, today's
/// HardRuleResetFooter) pinned at the bottom. NO paused banner on this page (PM 25-11; the To do page keeps
/// its own). All share the deps' ONE pause port and the page's store. While [autoRecordUi] is false no slot
/// is filled (no Auto-record control on the tab). A control that draws nothing leaves no gap.
/// The Set up action ([LevelsSlots.onSetUp]) is left null here: the integration slice (I2) opens the
/// Set up sheet (U-SETUP) from it and passes the bar's `onSetUp` to the U-CTRL bottom bar.
library;

import 'package:flutter/material.dart';

import '../../../ui/widgets/collapsing_padding.dart';
import 'hard_rule_pause_card.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'hard_rule_reset_footer.dart';
import 'levels_deps.dart';
import 'levels_tab.dart' show LevelsSlots;
import 'review_line.dart';

/// The slots for [d]. Empty while the Auto-record screens are off or there are no deps. The pause switch
/// needs a pause port (none = not drawn). The review line is drawn by the tab only while "Record receiver
/// details" is on, so it is built with details on.
LevelsSlots hardRuleSlotsFor(LevelsDeps? d) {
  if (!autoRecordUi || d == null) return const LevelsSlots();
  final pause = d.pause;
  final bulk = d.bulk;
  return LevelsSlots(
    pauseSwitch: pause == null
        ? null
        : (_) => CollapsingPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: HardRulePauseCard(key: const Key('slotPauseSwitch'), port: pause, bulk: bulk)),
    reviewLine: (_) => CollapsingPadding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: ReviewLine(key: const Key('slotReviewLine'), bulk: bulk, now: d.now)),
    // HANDOFF I2: pass `onSetUp` to the U-CTRL bottom bar once it takes it.
    bottomBar: (_, onSetUp) => SafeArea(
        top: false,
        child: CollapsingPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: HardRuleResetFooter(key: const Key('slotBottomBar'), bulk: bulk))),
  );
}
