import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/classification_dao.dart';
import '../../../data/db/counterparty_dao.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../theme/app_colors.dart';

/// §ADD.CATEGORY — category as inline chips: the type's classifications (or Cash's flat list), plus
/// "+ New" (creates one inline through the existing [ClassificationDao] —
/// same DAO `mpesa_classification_picker.dart`/`flat_classification_picker
/// .dart` already use, just a different, inline presentation); a known
/// counterparty's suggested classification comes first, pre-selected,
/// marked "· usual" (T18's auto-recognize gate, T12's
/// [CounterpartyDao.lookup]; this replaced the earlier standalone
/// suggestion pill); "Always use "X" for NAME" (T12's
/// make-automatic rule, shown inline: only for a known
/// counterparty without `auto_apply` yet, applied on save by the shell).
///
/// Owns its own DB reads (classification list + the counterparty
/// suggestion) so the shell only has to hand over which group/counterparty
/// is current and which classification is selected — same
/// reactive-on-prop-change contract (`didUpdateWidget` re-runs
/// [_load] whenever [sourceType]/[counterpartyKey] changes).
class CategoryChips extends StatefulWidget {
  const CategoryChips({
    super.key,
    required this.db,
    required this.sourceType,
    required this.counterpartyKey,
    required this.counterpartyDisplayName,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
    required this.autoApplyChecked,
    required this.onAutoApplyChanged,
  });

  final Database db;

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'`, `'CASH'`.
  final String sourceType;

  /// Already-derived key (`deriveCounterpartyKey`), `''` when there's
  /// nothing to look up (Cash, or identity capture off/incomplete).
  final String counterpartyKey;

  /// The receiver/business/shop name as currently typed — only used to
  /// render "Always use "X" for NAME"; this widget performs no lookup of
  /// its own with it.
  final String counterpartyDisplayName;

  final int? selectedId;
  final String? selectedName;
  final void Function(int id, String name) onSelected;

  /// Whether the "Always use" row is currently ticked for THIS
  /// counterparty (the shell tracks which key it was ticked for, same
  /// discipline as the old `_makeAutomaticKey`).
  final bool autoApplyChecked;
  final ValueChanged<bool> onAutoApplyChanged;

  @override
  State<CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<CategoryChips> {
  bool _loading = true;
  List<ClassificationItem> _items = const [];
  int? _createGroupId;
  CounterpartySuggestion? _suggestion;
  bool _creatingNew = false;
  String? _createError;
  final _newNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CategoryChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceType != widget.sourceType || oldWidget.counterpartyKey != widget.counterpartyKey) {
      // The tick (if any) belonged to the previous counterparty/group.
      if (widget.autoApplyChecked) widget.onAutoApplyChanged(false);
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
      _suggestion = null;
      _createError = null;
      _creatingNew = false;
    });
    final groups = await ClassificationDao.fetchGroups(widget.db);
    List<ClassificationItem> items;
    int createGroupId;
    if (widget.sourceType == 'CASH') {
      // Cash uses one flat classification list: new
      // classifications created from Cash default silently to Send Money.
      items = await ClassificationDao.fetchFlatActiveClassifications(widget.db);
      createGroupId = groups.firstWhere((g) => g.code == 'SEND_MONEY').id;
    } else {
      final group = groups.firstWhere((g) => g.code == widget.sourceType);
      items = await ClassificationDao.fetchActiveClassifications(widget.db, groupId: group.id);
      createGroupId = group.id;
    }
    CounterpartySuggestion? suggestion;
    if (widget.sourceType != 'CASH' && widget.counterpartyKey.isNotEmpty) {
      // T18: "when OFF, no lookup happens at all."
      final gateOn = await AppPrefs.readAutoRecognizeClassifications();
      if (gateOn) {
        suggestion = await CounterpartyDao.lookup(widget.db, sourceType: widget.sourceType, counterpartyKey: widget.counterpartyKey);
      }
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _createGroupId = createGroupId;
      _suggestion = suggestion;
      _loading = false;
    });
    // Pre-select the suggestion, but never stomp a choice the caller
    // already holds (a user pick, or a still-current earlier suggestion).
    if (suggestion != null && widget.selectedId == null) {
      widget.onSelected(suggestion.classificationId, suggestion.classificationName);
    }
  }

  Future<void> _createClassification() async {
    final groupId = _createGroupId;
    final name = _newNameController.text.trim();
    if (groupId == null || name.isEmpty) return;
    setState(() => _createError = null);
    try {
      final id = await ClassificationDao.createClassification(widget.db, groupId: groupId, name: name);
      _newNameController.clear();
      final items = widget.sourceType == 'CASH'
          ? await ClassificationDao.fetchFlatActiveClassifications(widget.db)
          : await ClassificationDao.fetchActiveClassifications(widget.db, groupId: groupId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _creatingNew = false;
      });
      widget.onSelected(id, name);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _createError = e.isUniqueConstraintError() ? 'A category named "$name" already exists.' : 'Could not create category: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()));
    }
    final palette = AppPalette.of(context);
    final suggestion = _suggestion;
    // The suggested classification comes first, per build step 6.
    final ordered = <ClassificationItem>[];
    if (suggestion != null) {
      final match = _items.where((i) => i.id == suggestion.classificationId);
      ordered.add(
        match.isNotEmpty
            ? match.first
            : ClassificationItem(id: suggestion.classificationId, groupId: _createGroupId ?? 0, name: suggestion.classificationName),
      );
    }
    for (final item in _items) {
      if (suggestion != null && item.id == suggestion.classificationId) continue;
      ordered.add(item);
    }
    final showAlwaysUse = suggestion != null && !suggestion.autoApply && widget.selectedId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final item in ordered)
              _chip(palette, item, isSuggested: suggestion != null && item.id == suggestion.classificationId),
            _newChip(palette),
          ],
        ),
        if (_creatingNew) _newRow(palette),
        if (showAlwaysUse) _alwaysUseRow(palette),
      ],
    );
  }

  Widget _chip(AppPalette palette, ClassificationItem item, {required bool isSuggested}) {
    final selected = widget.selectedId == item.id;
    return GestureDetector(
      key: Key('addCategoryChip_${item.id}'),
      onTap: () => widget.onSelected(item.id, item.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.primary : palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? palette.primary : (isSuggested ? palette.primary : palette.line),
            width: isSuggested && !selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? palette.onPrimary : palette.ink)),
            if (isSuggested) ...[
              const SizedBox(width: 5),
              Text('· usual', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected ? palette.onPrimary : palette.primary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _newChip(AppPalette palette) {
    if (_creatingNew) return const SizedBox.shrink();
    return GestureDetector(
      key: const Key('addCategoryNewButton'),
      onTap: () => setState(() => _creatingNew = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: palette.primary, width: 1.5)),
        child: Text('+ New', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.primary)),
      ),
    );
  }

  Widget _newRow(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('addCategoryNewField'),
                  controller: _newNameController,
                  style: TextStyle(color: palette.ink),
                  cursorColor: palette.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'New category name',
                    hintStyle: TextStyle(color: palette.mutedInk),
                    border: OutlineInputBorder(borderSide: BorderSide(color: palette.line)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.line)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 1.5)),
                  ),
                  onSubmitted: (_) => _createClassification(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('addCategoryNewAddButton'),
                onPressed: _createClassification,
                style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
                child: const Text('Add'),
              ),
            ],
          ),
          if (_createError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_createError!, key: const Key('addCategoryNewError'), style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D))),
            ),
        ],
      ),
    );
  }

  Widget _alwaysUseRow(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        key: const Key('addAlwaysUseCheckbox'),
        onTap: () => widget.onAutoApplyChanged(!widget.autoApplyChecked),
        child: Row(
          children: [
            Checkbox(
              value: widget.autoApplyChecked,
              activeColor: palette.primary,
              checkColor: palette.onPrimary,
              side: BorderSide(color: palette.mutedInk, width: 1.5),
              onChanged: (v) => widget.onAutoApplyChanged(v ?? false),
            ),
            Expanded(
              child: Text(
                'Always use "${widget.selectedName}" for ${widget.counterpartyDisplayName}',
                style: TextStyle(fontSize: 12.5, color: palette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
