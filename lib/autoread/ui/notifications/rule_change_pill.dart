/// §AUTOREAD.RULE_CHANGE_PILL - the one pill after a level change (0.2.2 item 2, slices U3 + U-PILL; mock
/// mock-remembered-v2 p-auto-pill, p-auto-pill-any, p-ask-pill).
///
/// [RuleChangePill] is the real [RuleChangeNotice]. The words and the drawn stages live in
/// §AUTOREAD.RULE_CHANGE_PILL_BODY (rule_change_pill_body.dart): name and category, never a phone number. Ask first
/// and Suggested show one line for [kRuleChangePillShortHold]. Auto-record shows its line for
/// [kRuleChangePillExpandAfter]; then the SAME pill box grows (F-2): the line stays and the limit line + button
/// ("Set a limit" / "Change", both call onChangeCeiling) appear under it, held [kRuleChangePillLongHold]. The change
/// is drawn at once (the grow animation is later, PM 25-11). Like PillToast (not edited: shared): top centre on the
/// app navigator's overlay ([appNavigatorKey]), a newer pill replaces the older one, a swipe up dismisses, one live
/// region plus an announcement for each stage, 44 px button, reduced motion = no slide or fade. Hold times grow with
/// a large text size (as PillToast does); the expand delay does not.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../ui/shell/app_messenger.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../../ui/widgets/tap_target.dart';
import '../../rules/rule_model.dart';
import '../levels/hard_rule_ports.dart';
import 'rule_change_pill_body.dart';

/// How long an Auto-record pill stays at stage 1 before it expands (signed: about 1.5 s).
const Duration kRuleChangePillExpandAfter = Duration(milliseconds: 1500);

/// How long an Ask first / Suggested pill stays (stage 1 only). The mock's own number: PM to confirm (W2).
const Duration kRuleChangePillShortHold = Duration(milliseconds: 2500);

/// How long stage 2 stays (F-2: longer than the 6 s toast minimum, so the limit line and its button can be read
/// and reached). The number is the builder's.
// PM to confirm
const Duration kRuleChangePillLongHold = Duration(seconds: 10);

/// The real notice: draws the one pill. Installed by RulesWiring.install (I1) as LevelsDeps.notice and as the
/// suggestions controller's notice.
class RuleChangePill implements RuleChangeNotice {
  const RuleChangePill();

  static _Live? _current;

  @override
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling, {String? categoryName}) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    dismissNow();
    PillToast.dismissNow(); // the newer message replaces a plain toast too, so two never stack
    final live = _Live();
    live.entry = OverlayEntry(
      builder: (context) => _RuleChangePillView(
        name: name,
        level: level,
        ceilingCents: ceilingCents,
        categoryName: categoryName,
        onChangeCeiling: onChangeCeiling,
        onGone: live.remove,
      ),
    );
    _current = live;
    overlay.insert(live.entry!);
  }

  /// Removes the pill on screen at once (no animation).
  static void dismissNow() {
    _current?.remove();
    _current = null;
  }

  /// True while a pill is on screen.
  static bool get isShowing => _current != null && !_current!.removed;
}

class _Live {
  OverlayEntry? entry;
  bool removed = false;

  void remove() {
    if (removed) return;
    removed = true;
    entry?.remove();
    entry?.dispose();
    if (identical(RuleChangePill._current, this)) RuleChangePill._current = null;
  }
}

class _RuleChangePillView extends StatefulWidget {
  const _RuleChangePillView({
    required this.name,
    required this.level,
    required this.ceilingCents,
    required this.categoryName,
    required this.onChangeCeiling,
    required this.onGone,
  });

  final String name;
  final RuleLevel level;
  final int? ceilingCents;
  final String? categoryName;
  final VoidCallback? onChangeCeiling;
  final VoidCallback onGone;

  @override
  State<_RuleChangePillView> createState() => _RuleChangePillViewState();
}

class _RuleChangePillViewState extends State<_RuleChangePillView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Timer? _timer;
  bool _started = false;
  bool _expanded = false;
  bool _leaving = false;
  bool _acted = false;
  double _dragUp = 0;

  bool get _expands => widget.level == RuleLevel.autoRecord;
  bool get _reduce => MediaQuery.of(context).disableAnimations;

  RuleChangePillLines get _lines => ruleChangePillLines(
        name: widget.name,
        level: widget.level,
        category: widget.categoryName,
        limitCents: widget.ceilingCents,
        stage2: _expanded,
        hasButton: widget.onChangeCeiling != null,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduce) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    _announce(_lines.spoken);
    _timer = _expands ? Timer(kRuleChangePillExpandAfter, _expand) : Timer(_scaled(kRuleChangePillShortHold), _leave);
  }

  /// [d] stretched for a large text size (never shorter than [d]).
  Duration _scaled(Duration d) {
    final scale = MediaQuery.of(context).textScaler.scale(14) / 14;
    return Duration(milliseconds: (d.inMilliseconds * math.max(1.0, scale)).round());
  }

  void _announce(String text) => SemanticsService.sendAnnouncement(View.of(context), text, Directionality.of(context));

  void _expand() {
    if (!mounted || _leaving) return;
    setState(() => _expanded = true);
    _announce(_lines.spoken);
    _timer = Timer(_scaled(kRuleChangePillLongHold), _leave);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    if (_reduce) {
      widget.onGone();
      return;
    }
    await _c.reverse();
    widget.onGone();
  }

  /// "Set a limit" and "Change" both land here.
  void _changeCeiling() {
    if (_acted) return;
    _acted = true;
    _timer?.cancel();
    widget.onGone(); // gone first, so the sheet (or a pill it shows) is not covered or removed with it
    widget.onChangeCeiling?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final maxW = math.min(kPillToastMaxWidth, width * 0.9);
    // Same colours as PillToast: light theme = dark pill; dark theme = dark card with a thin outline.
    final dark = p.brightness == Brightness.dark;
    final fill = dark ? p.card : p.ink;
    final ink = dark ? p.ink : p.background;
    final accent = dark ? p.primary : p.toastAction;
    final side = dark ? BorderSide(color: p.frameLine) : BorderSide.none;

    // One box for both stages (F-2): the same Material grows from a stadium to a rounded card, drawn at once.
    final pill = Material(
      type: MaterialType.canvas,
      color: fill,
      elevation: 6,
      shadowColor: Colors.black,
      shape: _expanded
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: side)
          : StadiumBorder(side: side),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, minWidth: _expanded ? maxW : 0, minHeight: kMinTapTarget),
        child: RuleChangePillBody(lines: _lines, ink: ink, accent: accent, onButton: _changeCeiling),
      ),
    );
    final slide = Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic));
    final animated = _reduce ? pill : SlideTransition(position: slide, child: FadeTransition(opacity: _c, child: pill));
    return Positioned.fill(
      child: SafeArea(
        minimum: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onVerticalDragUpdate: (d) {
              _dragUp = d.delta.dy < 0 ? _dragUp - d.delta.dy : 0;
              if (_dragUp > 16) _leave();
            },
            child: animated,
          ),
        ),
      ),
    );
  }
}
