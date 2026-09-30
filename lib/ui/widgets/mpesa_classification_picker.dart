import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/classification_dao.dart';
import '../theme/app_colors.dart';

/// T6 — Add — M-Pesa tab's classification picker.
///
/// Data dependencies: `classification_groups` (matching group, resolved from
/// the current Type) and `classifications` (active list within that group,
/// picker) — a single group's active classification list, no group-tab switching UI at
/// all, since the Type selector (Send Money/Paybill/Buy Goods) has already
/// fixed which group applies before this widget is ever shown.
///
/// Deliberately a separate widget from the other classification UIs, which
/// are the wrong shape here:
///   - Manage Classifications uses a 4-tab group switcher, where the user
///     picks WHICH group to browse. M-Pesa's Type selector already picked
///     the group; showing group tabs again here would let the user pick a
///     classification from a group that doesn't match their chosen Type,
///     defeating the whole point of
///     `trg_transactions_classification_scope_ins`'s group-scope guard.
///   - `FlatClassificationPicker` is a flat, cross-group,
///     name-deduplicated list, built for Cash, where there is no group
///     concept at all from the user's point of view.
/// A separate, purpose-built widget is more honest than forcing either
/// shape down to this one. `ClassificationDao` itself IS reused (not
/// rebuilt).
///
/// Re-resolves (loading state, then a fresh group+list lookup) whenever
/// [groupCode] changes — the caller passes a new [groupCode] whenever the
/// Type selector changes (manually, or via an overriding parse), and this
/// widget owns re-deriving its own group/list state from that, rather than
/// requiring the caller to key/remount it.
///
/// Same storage-agnostic pattern as every other picker in this codebase:
/// takes an already-open [Database] directly, plain
/// `ValueChanged<ClassificationItem>` callback, no hardcoded navigation.
class MpesaClassificationPicker extends StatefulWidget {
  const MpesaClassificationPicker({
    super.key,
    required this.db,
    required this.groupCode,
    required this.onClassificationSelected,
    this.palette = AppPalette.light,
  });

  /// Colour tokens; the light palette unless the caller passes the app's.
  final AppPalette palette;

  final Database db;

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'` — matches
  /// `classification_groups.code`/`transactions.source_type`'s literal DB
  /// values directly (the same raw string the Type selector already
  /// tracks). `'CASH'`/anything else has no matching group and is not a
  /// valid input here — the caller (this dispatch's own M-Pesa tab body)
  /// never shows this picker for Cash.
  final String groupCode;

  final ValueChanged<ClassificationItem> onClassificationSelected;

  @override
  State<MpesaClassificationPicker> createState() => _MpesaClassificationPickerState();
}

class _MpesaClassificationPickerState extends State<MpesaClassificationPicker> {
  final _newNameController = TextEditingController();

  bool _loading = true;
  int? _groupId;
  List<ClassificationItem> _items = const [];

  bool _creating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MpesaClassificationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupCode != widget.groupCode) {
      _load();
    }
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _createError = null;
    });
    final groups = await ClassificationDao.fetchGroups(widget.db);
    final group = groups.firstWhere((g) => g.code == widget.groupCode);
    final items = await ClassificationDao.fetchActiveClassifications(widget.db, groupId: group.id);
    if (!mounted) return;
    setState(() {
      _groupId = group.id;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _createClassification() async {
    final groupId = _groupId;
    final name = _newNameController.text.trim();
    if (groupId == null || name.isEmpty) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      await ClassificationDao.createClassification(widget.db, groupId: groupId, name: name);
      _newNameController.clear();
      final items = await ClassificationDao.fetchActiveClassifications(widget.db, groupId: groupId);
      if (!mounted) return;
      setState(() => _items = items);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _createError = e.isUniqueConstraintError()
            ? 'A classification named "$name" already exists.'
            : 'Could not create classification: $e';
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildList(),
        const SizedBox(height: 12),
        _buildCreateRow(),
      ],
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No classifications yet — add one below.',
          style: TextStyle(fontSize: 12.5, color: widget.palette.mutedInk),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++)
          _MpesaClassificationRow(
            key: Key('mpesaClassificationRow_${_items[i].id}'),
            item: _items[i],
            palette: widget.palette,
            showDivider: i != _items.length - 1,
            onTap: () => widget.onClassificationSelected(_items[i]),
          ),
      ],
    );
  }

  Widget _buildCreateRow() {
    final p = widget.palette;
    OutlineInputBorder border(Color c) => OutlineInputBorder(borderSide: BorderSide(color: c));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('mpesaPickerNewNameField'),
                controller: _newNameController,
                enabled: !_creating,
                style: TextStyle(color: p.ink),
                cursorColor: p.primary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New classification name',
                  hintStyle: TextStyle(color: p.mutedInk),
                  border: border(p.line),
                  enabledBorder: border(p.line),
                  focusedBorder: border(p.primary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _createClassification(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('mpesaPickerAddButton'),
              onPressed: _creating ? null : _createClassification,
              style: FilledButton.styleFrom(backgroundColor: p.primary, foregroundColor: p.onPrimary),
              child: _creating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
        if (_createError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _createError!,
              key: const Key('mpesaPickerCreateError'),
              style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
            ),
          ),
      ],
    );
  }
}

class _MpesaClassificationRow extends StatelessWidget {
  const _MpesaClassificationRow({
    super.key,
    required this.item,
    required this.palette,
    required this.showDivider,
    required this.onTap,
  });

  final ClassificationItem item;
  final AppPalette palette;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: showDivider
            ? BoxDecoration(border: Border(bottom: BorderSide(color: palette.line)))
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(item.name, style: TextStyle(fontSize: 14, color: palette.ink)),
            Icon(Icons.chevron_right, size: 18, color: palette.mutedInk),
          ],
        ),
      ),
    );
  }
}
