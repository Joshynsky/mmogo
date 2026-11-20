/// §WIDGET.PILL_TOAST — the modern top-center toast (0.2.1 beta, PM design).
///
/// One call shows it: `PillToast.show('Saved')` or with an action
/// `PillToast.show('Recorded Ksh 5.', actionLabel: 'Undo', onAction: undo)`. It floats at the top centre under
/// the status bar and notch, sizes itself to its text (up to 90% of the screen or 420 dp wide), slides down and
/// fades in, stays 6 s or more, then slides away. A swipe up dismisses it; a new toast replaces the old one; the
/// action runs once and dismisses the toast. It lives on the root navigator's overlay ([appNavigatorKey]), so it
/// shows on whatever page is open and never covers the system bars. Migrating a SnackBar is a one-line change.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../shell/app_messenger.dart';
import '../theme/app_colors.dart';
import 'tap_target.dart';

/// The shortest time a toast stays (longer for a big text size).
const Duration kPillToastMinDuration = Duration(seconds: 6);

/// The widest a pill gets, in dp (or 90% of the screen, whichever is less).
const double kPillToastMaxWidth = 420;

class PillToast {
  PillToast._();

  static _Live? _current;

  /// Shows [message] (replacing any toast on screen). Does nothing when no app is on screen yet.
  /// [onAction] runs once, after the toast is gone. [duration] is raised to 6 s and for a large text size.
  static void show(String message, {String? actionLabel, VoidCallback? onAction, Duration? duration}) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    dismissNow();
    final live = _Live();
    live.entry = OverlayEntry(
      builder: (context) => _PillToastView(
        key: live.view,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration ?? kPillToastMinDuration,
        onGone: live.remove,
      ),
    );
    _current = live;
    overlay.insert(live.entry!);
  }

  /// Removes the toast on screen at once (no animation).
  static void dismissNow() {
    _current?.remove();
    _current = null;
  }

  /// True while a toast is on screen.
  static bool get isShowing => _current != null && !_current!.removed;
}

class _Live {
  final GlobalKey<_PillToastViewState> view = GlobalKey<_PillToastViewState>();
  OverlayEntry? entry;
  bool removed = false;

  void remove() {
    if (removed) return;
    removed = true;
    entry?.remove();
    entry?.dispose();
    if (identical(PillToast._current, this)) PillToast._current = null;
  }
}

class _PillToastView extends StatefulWidget {
  const _PillToastView({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onGone,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_PillToastView> createState() => _PillToastViewState();
}

class _PillToastViewState extends State<_PillToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Timer? _timer;
  bool _started = false;
  bool _leaving = false;
  bool _acted = false;
  double _dragUp = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final mq = MediaQuery.of(context);
    if (mq.disableAnimations) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    final scale = mq.textScaler.scale(14) / 14;
    final ms = (widget.duration.inMilliseconds * math.max(1.0, scale)).round();
    _timer = Timer(Duration(milliseconds: math.max(ms, kPillToastMinDuration.inMilliseconds)), _leave);
    SemanticsService.sendAnnouncement(View.of(context), widget.message, Directionality.of(context));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (MediaQuery.of(context).disableAnimations) {
      widget.onGone();
      return;
    }
    await _c.reverse();
    widget.onGone();
  }

  void _act() {
    if (_acted) return;
    _acted = true;
    _timer?.cancel();
    widget.onGone(); // gone first, so a toast the action shows is not removed with it
    widget.onAction?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final maxW = math.min(kPillToastMaxWidth, width * 0.9);
    // Light theme: dark pill, light text. Dark theme: dark card with a thin outline, so it never looks like a
    // bright patch on a dark page; the action uses the bright primary.
    final dark = p.brightness == Brightness.dark;
    final fill = dark ? p.card : p.ink;
    final textColor = dark ? p.ink : p.background;
    final accent = dark ? p.primary : p.toastAction;
    final text = Text(
      widget.message,
      style: TextStyle(color: textColor, fontSize: 14, height: 1.3, fontWeight: FontWeight.w500),
    );
    final pill = Material(
      type: MaterialType.canvas,
      color: fill,
      elevation: 6,
      shadowColor: Colors.black,
      shape: StadiumBorder(side: dark ? BorderSide(color: p.frameLine) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, minHeight: kMinTapTarget),
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 16, end: widget.actionLabel == null ? 18 : 6, top: 6, bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(Icons.check_circle_rounded, size: 18, color: accent)),
              const SizedBox(width: 10),
              Flexible(child: Semantics(container: true, liveRegion: true, child: text)),
              if (widget.actionLabel != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _act,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  child: Text(widget.actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final slide = Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic));
    final animated = MediaQuery.of(context).disableAnimations
        ? pill
        : SlideTransition(position: slide, child: FadeTransition(opacity: _c, child: pill));
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
