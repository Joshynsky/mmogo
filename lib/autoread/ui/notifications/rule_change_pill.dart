/// §AUTOREAD.RULE_CHANGE_PILL - the one pill after a level change (0.2.2 item 2, slice U3; mock pill-1..pill-4).
///
/// [RuleChangePill] is the real [RuleChangeNotice]. Stage 1 says "{name} set to {level}". Ask first and Suggested
/// end there after [kRuleChangePillShortHold]. Auto-record stays [kRuleChangePillExpandAfter], then the SAME pill
/// grows into stage 2 ("{name} is on Auto-record with ..." + "You can change this." + "Change ceiling"), which stays
/// at least [kPillToastMinDuration]. Like PillToast (not edited: shared): top centre on the app navigator's
/// overlay ([appNavigatorKey]), a newer pill replaces the older one, a swipe up dismisses, live region plus an
/// announcement for each stage, 44 px button, reduced motion = no slide, fade or resize animation. Hold times grow
/// with a large text size (as PillToast does); the expand delay does not.
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
import '../levels/hard_rule_copy.dart';
import '../levels/hard_rule_ports.dart';

/// How long an Auto-record pill stays at stage 1 before it expands (signed: about 1.5 s).
const Duration kRuleChangePillExpandAfter = Duration(milliseconds: 1500);

/// How long an Ask first / Suggested pill stays (stage 1 only). The mock's own number: PM to confirm.
const Duration kRuleChangePillShortHold = Duration(milliseconds: 2500);

/// Stage 2 stays at least this long (the app's toast minimum).
const Duration kRuleChangePillLongHold = kPillToastMinDuration;

/// The real notice: draws the one pill. Not installed anywhere yet (slice I1 passes it to LevelsDeps and the
/// suggestions controller).
class RuleChangePill implements RuleChangeNotice {
  const RuleChangePill();

  static _Live? _current;

  @override
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling) {
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
    required this.onChangeCeiling,
    required this.onGone,
  });

  final String name;
  final RuleLevel level;
  final int? ceilingCents;
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
    _announce(hardPillStage1(widget.name, widget.level));
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
    _announce('${hardPillStage2(widget.name, widget.ceilingCents)} $kHardPillStage2Sub');
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

    final Widget body = _expanded ? _stage2(ink, accent) : _stage1(ink, accent);
    final pill = Material(
      type: MaterialType.canvas,
      color: fill,
      elevation: 6,
      shadowColor: Colors.black,
      shape: _expanded
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: dark ? BorderSide(color: p.frameLine) : BorderSide.none,
            )
          : StadiumBorder(side: dark ? BorderSide(color: p.frameLine) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, minWidth: _expanded ? maxW : 0, minHeight: kMinTapTarget),
        child: _reduce
            ? body
            : AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic, child: body),
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

  Widget _stage1(Color ink, Color accent) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 18, top: 6, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(Icons.check_circle_rounded, size: 18, color: accent)),
            const SizedBox(width: 10),
            Flexible(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  hardPillStage1(widget.name, widget.level),
                  style: TextStyle(color: ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _stage2(Color ink, Color accent) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 8, top: 12, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Text(
                      hardPillStage2(widget.name, widget.ceilingCents),
                      style: TextStyle(color: ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kHardPillStage2Sub,
                    style: TextStyle(color: ink.withValues(alpha: 0.9), fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
            if (widget.onChangeCeiling != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _changeCeiling,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: const Text(kHardPillChangeCeiling),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      );
}
