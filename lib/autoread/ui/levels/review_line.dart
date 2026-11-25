/// §AUTOREAD.LEVELS.REVIEW_LINE: the line at the top of the Remembered page's second tab after a
/// restore (0.2.2 item 2, slice U6, mock rst-line): "{n} people were on Auto-record. They are on Ask
/// first until you confirm." with Review, which opens the review sheet. n comes only from the rules'
/// `autoPending` mark ([RuleBulkOps.pendingAutoPeople]): someone on Ask first by their own choice is
/// never counted. Draws nothing when n is 0, when "Record receiver details" is off, or while
/// [autoRecordUi] is false. Re-reads after every store change. Built for U5's review-line slot (I1).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/tap_target.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart';
import 'review_sheet.dart';

class ReviewLine extends StatefulWidget {
  const ReviewLine({super.key, required this.bulk, this.detailsOn = true, this.now = DateTime.now});

  /// The page's rule operations (its store is the one the review writes to).
  final RuleBulkOps bulk;

  /// "Record receiver details": OFF draws nothing (the page shows its own details-off line).
  final bool detailsOn;

  final DateTime Function() now;

  @override
  State<ReviewLine> createState() => _ReviewLineState();
}

class _ReviewLineState extends State<ReviewLine> {
  List<ReceiverRule> _pending = const [];
  StreamSubscription<void>? _sub;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _load();
  }

  @override
  void didUpdateWidget(ReviewLine old) {
    super.didUpdateWidget(old);
    if (!identical(old.bulk.store, widget.bulk.store)) {
      _sub?.cancel();
      _listen();
      _load();
    }
  }

  void _listen() => _sub = widget.bulk.store.changes.listen((_) => _load());

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    var list = const <ReceiverRule>[];
    try {
      list = await widget.bulk.pendingAutoPeople();
    } catch (_) {}
    if (mounted) setState(() => _pending = list);
  }

  Future<void> _review() async {
    if (_open || _pending.isEmpty) return;
    _open = true;
    try {
      await reviewRestoredPeople(context, store: widget.bulk.store, people: _pending, now: widget.now);
    } finally {
      _open = false;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = _pending.length;
    if (!autoRecordUi || !widget.detailsOn || n == 0) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('reviewLine'),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: p.tint,
          border: Border.all(color: p.primary, width: 1.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hardReviewLine(n),
                key: const Key('reviewLineText'),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: p.tintInk),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              key: const Key('reviewLineButton'),
              onPressed: _review,
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                foregroundColor: p.tintInk,
                textStyle: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
              ),
              child: const Text(kHardReviewButton),
            ),
          ],
        ),
      ),
    );
  }
}
