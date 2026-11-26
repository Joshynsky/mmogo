/// §AUTOREAD.LEVELS.HARD_RULE_RESET_FOOTER: the BOTTOM BAR of the Remembered page's second tab (item 2
/// redesign, mock-remembered-v2 page-all / page-reset / page-empty): a small red "Reset everyone to
/// Suggested" link at the start, the "Set up" button at the end ([HardRuleResetFooter.onSetUp]; null =
/// hidden), stuck to the bottom inside a SafeArea. When the two do not fit on one line (200% text) the bar
/// wraps: the link on line 1 at the start, Set up on line 2 at the end. The link is hidden while nobody
/// would change (empty page, everyone Suggested); it follows the rule store's changes.
/// Reset shows a counts-only confirm ([HardRuleResetDialog], no person is named) and goes through
/// [RuleBulkOps.resetAllToSuggested]: rules stay (level Suggested, limit and restore mark cleared), each
/// person's chosen Suggest categories are kept (PM 25-11, Q2), nobody is raised, the pause switch is never
/// touched. Draws nothing while [autoRecordUi] is false (dormant).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart';
import 'levels_copy.dart' show kLevelSheetCancel, kLevelSheetSaveFailed;

class HardRuleResetFooter extends StatefulWidget {
  const HardRuleResetFooter({super.key, required this.bulk, this.onDone, this.onSetUp});

  final RuleBulkOps bulk;

  /// After a reset that changed someone (the page reloads its list). Gets the number changed.
  final ValueChanged<int>? onDone;

  /// Opens the Set up sheet (the tab's action; null = no Set up button).
  final VoidCallback? onSetUp;

  @override
  State<HardRuleResetFooter> createState() => _HardRuleResetFooterState();
}

class _HardRuleResetFooterState extends State<HardRuleResetFooter> {
  bool _busy = false;

  /// How many a reset would change; null = not read yet or the read failed.
  int? _n;
  bool _failed = false;
  StreamSubscription<void>? _sub;
  Object? _store;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant HardRuleResetFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_store, widget.bulk.store)) _follow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _follow() {
    _sub?.cancel();
    _store = widget.bulk.store;
    _sub = widget.bulk.store.changes.listen((_) => _count());
    _count();
  }

  Future<void> _count() async {
    final seq = ++_seq;
    int? n;
    var failed = false;
    try {
      n = await widget.bulk.resetCount();
    } catch (_) {
      failed = true;
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _n = n;
      _failed = failed;
    });
  }

  /// The link shows when someone would change, or when the count could not be read (the tap then says
  /// the save failed, as before).
  bool get _showReset => _failed || (_n ?? 0) > 0;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    int n;
    try {
      n = await widget.bulk.resetCount();
    } catch (_) {
      PillToast.show(kLevelSheetSaveFailed);
      return;
    }
    if (!mounted) return;
    if (n == 0) {
      // The count changed under the link: nothing to confirm, say so with the same count line.
      PillToast.show(hardResetToast(0));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (_) => HardRuleResetDialog(count: n));
    if (ok != true) return;
    int done;
    try {
      done = await widget.bulk.resetAllToSuggested();
    } catch (_) {
      done = 0;
    }
    PillToast.show(done == 0 ? kLevelSheetSaveFailed : hardResetToast(done));
    if (done > 0) widget.onDone?.call(done);
  }

  @override
  Widget build(BuildContext context) {
    if (!autoRecordUi) return const SizedBox.shrink();
    final setUp = widget.onSetUp;
    final reset = _showReset;
    if (!reset && setUp == null) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return DecoratedBox(
      key: const Key('hardBottomBar'),
      decoration: BoxDecoration(color: p.background, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: HardBottomBarLayout(
            gap: 8,
            children: [
              reset ? _resetLink(p) : const SizedBox.shrink(),
              setUp == null ? const SizedBox.shrink() : _setUpButton(p, setUp),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resetLink(AppPalette p) => TextButton(
        key: const Key('hardResetButton'),
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: p.error,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.25,
            decoration: TextDecoration.underline,
          ),
        ),
        onPressed: _busy ? null : _tap,
        child: const Text(kHardResetButton, textAlign: TextAlign.start),
      );

  Widget _setUpButton(AppPalette p, VoidCallback onSetUp) => Semantics(
        container: true,
        button: true,
        label: kHardSetUpTitle,
        onTap: onSetUp,
        excludeSemantics: true,
        child: FilledButton(
          key: const Key('hardSetUpButton'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 14, 4),
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          onPressed: onSetUp,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(kHardSetUpButton)),
            SizedBox(width: 8),
            Icon(Icons.add_circle_outline, size: 22),
          ]),
        ),
      );
}

/// Two children: [children.first] at the start, [children.last] at the end, on one line when they fit
/// (vertically centred); otherwise the first on line 1 at the start and the last on line 2 at the end,
/// [gap] apart. A child of zero width takes no room. Start and end follow the text direction.
class HardBottomBarLayout extends MultiChildRenderObjectWidget {
  const HardBottomBarLayout({super.key, this.gap = 8, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderHardBottomBar(textDirection: Directionality.of(context), gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderHardBottomBar renderObject) {
    renderObject
      ..textDirection = Directionality.of(context)
      ..gap = gap;
  }
}

/// Parent data of [RenderHardBottomBar]'s two children.
class HardBottomBarParentData extends ContainerBoxParentData<RenderBox> {}

/// The render box of [HardBottomBarLayout].
class RenderHardBottomBar extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, HardBottomBarParentData>, RenderBoxContainerDefaultsMixin<RenderBox, HardBottomBarParentData> {
  RenderHardBottomBar({required TextDirection textDirection, required double gap})
      : _textDirection = textDirection,
        _gap = gap;

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! HardBottomBarParentData) child.parentData = HardBottomBarParentData();
  }

  bool _oneLine(Size a, Size b, double maxWidth) => a.width == 0 || b.width == 0 || a.width + _gap + b.width <= maxWidth;

  Size _sizeFor(Size a, Size b, BoxConstraints c) {
    final w = c.hasBoundedWidth ? c.maxWidth : a.width + _gap + b.width;
    final h = _oneLine(a, b, w)
        ? math.max(a.height, b.height)
        : a.height + _gap + b.height;
    return c.constrain(Size(w, h));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final loose = constraints.loosen();
    final a = firstChild!.getDryLayout(loose);
    final b = lastChild!.getDryLayout(loose);
    return _sizeFor(a, b, constraints);
  }

  @override
  void performLayout() {
    assert(childCount == 2, 'HardBottomBarLayout takes exactly two children');
    final loose = constraints.loosen();
    final first = firstChild!;
    final last = lastChild!;
    first.layout(loose, parentUsesSize: true);
    last.layout(loose, parentUsesSize: true);
    final a = first.size;
    final b = last.size;
    size = _sizeFor(a, b, constraints);
    final rtl = _textDirection == TextDirection.rtl;
    double startX(Size s) => rtl ? size.width - s.width : 0;
    double endX(Size s) => rtl ? 0 : size.width - s.width;
    final pa = first.parentData! as HardBottomBarParentData;
    final pb = last.parentData! as HardBottomBarParentData;
    if (_oneLine(a, b, size.width)) {
      pa.offset = Offset(startX(a), (size.height - a.height) / 2);
      pb.offset = Offset(endX(b), (size.height - b.height) / 2);
    } else {
      pa.offset = Offset(startX(a), 0);
      pb.offset = Offset(endX(b), a.height + _gap);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(firstChild!.getMinIntrinsicWidth(height), lastChild!.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height) + _gap + lastChild!.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicHeight(double width) {
    final a = firstChild!;
    final b = lastChild!;
    final aw = a.getMaxIntrinsicWidth(double.infinity);
    final bw = b.getMaxIntrinsicWidth(double.infinity);
    final one = aw == 0 || bw == 0 || aw + _gap + bw <= width;
    final ah = a.getMaxIntrinsicHeight(width);
    final bh = b.getMaxIntrinsicHeight(width);
    return one ? math.max(ah, bh) : ah + _gap + bh;
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// "Reset {n} people to Suggested?": counts only. Pops true only on Reset.
class HardRuleResetDialog extends StatelessWidget {
  const HardRuleResetDialog({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const minSize = Size(64, 44);
    return AlertDialog(
      title: Text(hardResetTitle(count), key: const Key('hardResetTitle')),
      content: const SingleChildScrollView(child: Text(kHardResetBody, key: Key('hardResetBody'))),
      actions: [
        TextButton(
          key: const Key('hardResetCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kLevelSheetCancel),
        ),
        FilledButton(
          key: const Key('hardResetOk'),
          style: FilledButton.styleFrom(minimumSize: minSize, backgroundColor: p.error, foregroundColor: p.onDelete),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kHardResetOk),
        ),
      ],
    );
  }
}
