import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import '../../widgets/type_icon.dart';
import 'format.dart';

/// §ANALYTICS.TX_ROW — one transaction row: swipe right = Edit, left = Delete, tap = open.
/// One row (mock `.brow`/`.bin`). Dragging clamps at ±110; released past
/// 60 it settles open at ±84 over the Edit (right) or Delete (left) action,
/// which is then tapped. Tapping the row itself opens it in the edit form
/// (which can also delete) — the non-gesture path (WCAG 2.5.1, PM decision
/// 2026-09-25). With a keyboard: E = edit, Delete = delete.
class AnalyticsSwipeRow extends StatefulWidget {
  const AnalyticsSwipeRow({
    super.key,
    required this.rowKey,
    required this.palette,
    required this.tx,
    required this.highlighted,
    required this.forceClosed,
    required this.onOpened,
    required this.onEdit,
    required this.onDelete,
  });

  final GlobalKey rowKey;
  final AppPalette palette;
  final AnalyticsTransactionRow tx;
  final bool highlighted;

  /// Another row was opened (or the list changed): close this one.
  final bool forceClosed;
  final ValueChanged<bool> onOpened;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<AnalyticsSwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<AnalyticsSwipeRow> {
  static const _clamp = 110.0;
  static const _commit = 60.0;
  static const _open = 84.0;

  double _dx = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(AnalyticsSwipeRow old) {
    super.didUpdateWidget(old);
    if (widget.forceClosed && !_dragging && _dx != 0) _dx = 0;
  }

  void _settle() {
    final open = _dx > _commit ? _open : (_dx < -_commit ? -_open : 0.0);
    setState(() {
      _dragging = false;
      _dx = open;
    });
    widget.onOpened(open != 0);
  }

  void _onTap() {
    if (_dx != 0) {
      setState(() => _dx = 0);
      widget.onOpened(false);
      return;
    }
    widget.onEdit();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final tx = widget.tx;
    final isCash = tx.sourceType == 'CASH';
    final color = p.typeColor(tx.sourceType);
    final meta = [tx.classificationName, analyticsHhmm(tx.occurredAt), if (!isCash) tx.displayCode].join(' · ');
    final fee = tx.transactionCostCents ?? 0;

    Widget action({required Key key, required bool edit}) {
      final fg = edit ? p.onPrimary : p.onDelete;
      return Material(
        color: edit ? p.primary : p.diffUp,
        child: InkWell(
          key: key,
          onTap: edit ? widget.onEdit : widget.onDelete,
          child: SizedBox(
            width: _open,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(edit ? Icons.edit_outlined : Icons.delete_outline_rounded, size: 18, color: fg),
                const SizedBox(height: 3),
                Text(
                  edit ? 'Edit' : 'Delete',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final content = AnimatedContainer(
      key: widget.rowKey,
      duration: const Duration(milliseconds: 600),
      color: widget.highlighted ? p.highlight : p.card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          TypeIconTile(code: tx.sourceType, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 1),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.mutedInk),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatKsh(tx.amountCents),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFeatures: tabularFigures, color: p.ink),
              ),
              if (fee > 0) ...[
                const SizedBox(height: 1),
                Text('+ ${kshTrim(fee)} fee', style: TextStyle(fontSize: 10.5, color: p.mutedInk)),
              ],
            ],
          ),
        ],
      ),
    );

    return Semantics(
      label:
          '${tx.displayName}, ${formatKsh(tx.amountCents)}, ${sourceTypeName(tx.sourceType)}, $meta. '
          'Tap to edit. Press E to edit, Delete to delete',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Edit'): widget.onEdit,
        const CustomSemanticsAction(label: 'Delete'): widget.onDelete,
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.keyE) {
            widget.onEdit();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
            widget.onDelete();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  action(key: Key('analyticsRowEdit-${tx.id}'), edit: true),
                  action(key: Key('analyticsRowDelete-${tx.id}'), edit: false),
                ],
              ),
            ),
            // The transform sits outside the gesture detector, so an open row
            // only takes taps where its content actually is — the revealed
            // action beside it gets its own taps.
            AnimatedContainer(
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.ease,
              transform: Matrix4.translationValues(_dx, 0, 0),
              child: GestureDetector(
                key: Key('analyticsRow-${tx.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: _onTap,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(-_clamp, _clamp)),
                onHorizontalDragEnd: (_) => _settle(),
                onHorizontalDragCancel: _settle,
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
