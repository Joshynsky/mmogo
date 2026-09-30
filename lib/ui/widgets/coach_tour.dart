import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/prefs/app_prefs.dart';
import '../theme/app_colors.dart';

/// One step of a [CoachTour]: a spotlight on [target] plus a bubble with
/// [text]. If [target] is null, not built, or not laid out, the step shows no
/// spotlight and the bubble is centred.
///
/// [actionLabel]/[onAction] make the cross-page "Take me there" button, shown
/// on that step only. Tapping it runs [onAction] and ends the tour (marked
/// seen), so the destination page can start its own tour.
class CoachStep {
  const CoachStep({
    required this.target,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.onEnter,
  });

  final GlobalKey? target;
  final String text;

  /// Runs when the step becomes current, before its spotlight is measured
  /// (e.g. scroll [target] into view). The overlay re-measures next frame.
  final VoidCallback? onEnter;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// A [CoachStep.onEnter] helper: jumps the scrollable holding [key]'s widget
/// so it shows, a little above the middle. No-op if it is not built.
void scrollIntoView(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null || !ctx.mounted) return;
  Scrollable.ensureVisible(ctx, alignment: 0.3, duration: Duration.zero);
}

const coachTourBubbleKey = Key('coachTourBubble');
const coachTourNextKey = Key('coachTourNext');
const coachTourSkipKey = Key('coachTourSkip');
const coachTourStepCounterKey = Key('coachTourStepCounter');
const coachTourActionKey = Key('coachTourAction');

/// A dimmed-screen coach-mark tour (spotlight + bubble, "n of N", Next/Done,
/// Skip). Palette colours only.
class CoachTour {
  CoachTour._();

  /// Test switch: while true, [maybeStart] never shows a tour, so page tests
  /// need not seed the seen flags (`test/flutter_test_config.dart` sets it;
  /// the tour's own tests clear it). Replay via [start] is unaffected.
  @visibleForTesting
  static bool autoStartDisabled = false;

  /// Shows the tour only if [pageId]'s tour has not been seen. Marks it seen
  /// on Done or Skip. Completes when the tour closes (immediately if it was
  /// already seen, or [steps] is empty, or [context] is gone).
  static Future<void> maybeStart(
    BuildContext context, {
    required String pageId,
    required List<CoachStep> steps,
  }) async {
    if (steps.isEmpty || autoStartDisabled) return;
    if (await AppPrefs.readTourSeen(pageId)) return;
    if (!context.mounted) return;
    await start(context, pageId: pageId, steps: steps);
  }

  /// Replay: shows the tour regardless of the seen flag (still marks seen).
  static Future<void> start(
    BuildContext context, {
    required String pageId,
    required List<CoachStep> steps,
  }) {
    if (steps.isEmpty) return Future.value();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value();
    final done = Completer<void>();
    late OverlayEntry entry;
    void finish() {
      if (done.isCompleted) return;
      done.complete();
      entry.remove();
      AppPrefs.markTourSeen(pageId);
    }

    entry = OverlayEntry(
      builder: (_) => _CoachTourOverlay(steps: steps, onFinish: finish),
    );
    overlay.insert(entry);
    return done.future;
  }
}

class _CoachTourOverlay extends StatefulWidget {
  const _CoachTourOverlay({required this.steps, required this.onFinish});

  final List<CoachStep> steps;
  final VoidCallback onFinish;

  @override
  State<_CoachTourOverlay> createState() => _CoachTourOverlayState();
}

class _CoachTourOverlayState extends State<_CoachTourOverlay> {
  int _index = 0;

  CoachStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _enterStep();
  }

  /// Runs the step's [CoachStep.onEnter], then re-measures once the frame it
  /// caused (e.g. a scroll jump) has laid out.
  void _enterStep() {
    final cb = _step.onEnter;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    });
  }

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      setState(() => _index++);
      _enterStep();
    }
  }

  void _action() {
    final cb = _step.onAction;
    widget.onFinish();
    cb?.call();
  }

  /// The target's rect in this overlay's coordinates, or null when it is not
  /// currently laid out.
  Rect? _targetRect() {
    final ctx = _step.target?.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final box = ctx.findRenderObject();
    final me = context.findRenderObject();
    if (box is! RenderBox || me is! RenderBox) return null;
    if (!box.attached || !box.hasSize || !me.attached || !me.hasSize) {
      return null;
    }
    try {
      final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
      return topLeft & box.size;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final raw = _targetRect();
    final visible = Offset.zero & size;
    final rect = (raw == null || !raw.overlaps(visible))
        ? null
        : raw.inflate(6).intersect(visible);

    const gap = 12.0;
    const margin = 16.0;
    final topLimit = padding.top + 8;
    final bottomLimit = size.height - padding.bottom - 8;

    Widget bubble(double maxHeight) => _Bubble(
      palette: p,
      step: _step,
      index: _index,
      total: widget.steps.length,
      isLast: _isLast,
      maxHeight: maxHeight,
      onNext: _next,
      onSkip: widget.onFinish,
      onAction: _step.actionLabel != null ? _action : null,
    );

    final Widget placed;
    if (rect == null) {
      placed = Positioned.fill(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            topLimit,
            margin,
            size.height - bottomLimit,
          ),
          child: Center(child: bubble(bottomLimit - topLimit)),
        ),
      );
    } else {
      final below = bottomLimit - rect.bottom - gap;
      final above = rect.top - gap - topLimit;
      if (below >= above) {
        placed = Positioned(
          left: margin,
          right: margin,
          top: rect.bottom + gap,
          child: bubble(math.max(below, 80)),
        );
      } else {
        placed = Positioned(
          left: margin,
          right: margin,
          bottom: size.height - rect.top + gap,
          child: bubble(math.max(above, 80)),
        );
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The scrim swallows every tap: the tour is modal.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _ScrimPainter(
                rect: rect,
                color: p.ink.withValues(alpha: 0.72),
              ),
            ),
          ),
          placed,
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.rect, required this.color});

  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final r = rect;
    if (r != null) {
      path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)));
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.rect != rect || old.color != color;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.palette,
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.maxHeight,
    required this.onNext,
    required this.onSkip,
    required this.onAction,
  });

  final AppPalette palette;
  final CoachStep step;
  final int index;
  final int total;
  final bool isLast;
  final double maxHeight;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        key: coachTourBubbleKey,
        decoration: BoxDecoration(
          color: p.card,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                step.text,
                style: TextStyle(fontSize: 14, height: 1.35, color: p.ink),
              ),
              if (onAction != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: coachTourActionKey,
                    onPressed: onAction,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.primary,
                      side: BorderSide(color: p.primary),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(step.actionLabel!),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  Text(
                    '${index + 1} of $total',
                    key: coachTourStepCounterKey,
                    style: TextStyle(fontSize: 12.5, color: p.mutedInk),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        key: coachTourSkipKey,
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: p.mutedInk,
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Skip'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        key: coachTourNextKey,
                        onPressed: onNext,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: p.onPrimary,
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(isLast ? 'Done' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
