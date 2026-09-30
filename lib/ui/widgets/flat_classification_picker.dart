import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/classification_dao.dart';
import '../theme/app_colors.dart';

/// T3 — Add — Cash tab's classification picker.
///
/// For Cash the group-tab step is skipped entirely: the picker displays one
/// flat, name-deduplicated classification list merged from every enabled
/// group directly. Cash is a direct payment for whatever reason (rent, a person, a
/// barber...), never conceptually "Send Money"/"Paybill"/"Buy Goods" — so
/// this widget renders ONE flat list (backed by
/// `ClassificationDao.fetchFlatActiveClassifications`), no group tabs at
/// all, with inline create-new.
///
/// Deliberately NOT a group-tab widget — a group-tabs-plus-per-group-list
/// shape is the opposite of what Cash needs (a flat list with no group-tab
/// step); a separate, purpose-built widget is more honest than forcing
/// group-tab code down to zero tabs. `ClassificationDao` itself IS
/// reused/extended (not rebuilt).
///
/// A classification created from this picker is stored under the Send
/// Money group as a silent implementation detail, never shown to the user
/// — new classifications created from the cash flow are still stored under
/// a group_id (the schema requires one) but default silently to the Send
/// Money group. This is a binding, disclosed requirement, not a workaround.
///
/// Same storage-agnostic pattern as T7/T14: takes an already-open
/// [Database] directly, plain `ValueChanged<ClassificationItem>` callback,
/// no hardcoded navigation.
class FlatClassificationPicker extends StatefulWidget {
  const FlatClassificationPicker({
    super.key,
    required this.db,
    required this.onClassificationSelected,
    this.palette = AppPalette.light,
  });

  /// Colour tokens; the light palette unless the caller passes the app's.
  final AppPalette palette;

  final Database db;
  final ValueChanged<ClassificationItem> onClassificationSelected;

  @override
  State<FlatClassificationPicker> createState() => _FlatClassificationPickerState();
}

class _FlatClassificationPickerState extends State<FlatClassificationPicker> {
  final _newNameController = TextEditingController();

  bool _loading = true;
  List<ClassificationItem> _items = const [];
  int? _sendMoneyGroupId;

  bool _creating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ClassificationDao.fetchFlatActiveClassifications(widget.db),
      ClassificationDao.fetchGroups(widget.db),
    ]);
    if (!mounted) return;
    final items = results[0] as List<ClassificationItem>;
    final groups = results[1] as List<ClassificationGroup>;
    // New cash-flow classifications default silently to
    // Send Money's group — a real, intended-by-design lookup, not a
    // "special-case" this project's discipline warns against (that
    // discipline targets `code == 'POCHI_LA_BIASHARA'`-shaped branching in
    // *rendering* logic, which this widget has none of).
    final sendMoney = groups.firstWhere((g) => g.code == 'SEND_MONEY');
    setState(() {
      _items = items;
      _sendMoneyGroupId = sendMoney.id;
      _loading = false;
    });
  }

  Future<void> _createClassification() async {
    final groupId = _sendMoneyGroupId;
    final name = _newNameController.text.trim();
    if (groupId == null || name.isEmpty) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      await ClassificationDao.createClassification(widget.db, groupId: groupId, name: name);
      _newNameController.clear();
      final items = await ClassificationDao.fetchFlatActiveClassifications(widget.db);
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
          'No classifications yet — add one below (e.g. Family/Friends, Rent, Barber, Mechanic).',
          style: TextStyle(fontSize: 12.5, color: widget.palette.mutedInk),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++)
          _FlatClassificationRow(
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
                key: const Key('flatPickerNewNameField'),
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
              key: const Key('flatPickerAddButton'),
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
              style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
            ),
          ),
      ],
    );
  }
}

class _FlatClassificationRow extends StatelessWidget {
  const _FlatClassificationRow({
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
