import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/app_database.dart';
import '../../data/db/classification_dao.dart';
import '../shell/secondary_scaffold.dart';
import '../theme/app_colors.dart';

/// T8 — Manage Classifications. Own dedicated page (secondary chrome
/// tier), reached from Settings: an active classification list per group
/// + a separate inactive/deleted list, create/rename/soft-delete (with a
/// real `COUNT(*)`-by-classification delete-confirmation message) and
/// restore (`active=0 -> 1`) — restore is real in-scope work, not a
/// one-way mechanism.
///
/// Reuses T7's `ClassificationDao` (extended this dispatch with
/// `fetchInactiveClassifications`/`renameClassification`/
/// `softDeleteClassification`/`restoreClassification`/
/// `countTransactionsForClassification`) as the sole data layer. This
/// page draws its own group tabs (see [_ManageGroupTab]; disabled-tab
/// styling for Pochi) rather than sharing a picker widget, because its
/// two-lists-per-group shape (active + inactive, each with its own action
/// set) does not fit a "select this classification for use" picker.
///
/// T26 "i think it should recolor the entire app": follows the chosen
/// palette (`SecondaryScaffold(followPalette: true)`, every colour a
/// palette token), same as T24's Profile rework. The classification group
/// selector and the active/inactive pickers are only reworked as far as
/// this page renders them — `lib/ui/widgets/*` used by Add is out of
/// scope (Add itself is out of scope until its own rework).
class ManageClassificationsScreen extends StatefulWidget {
  const ManageClassificationsScreen({super.key, this.db});

  /// Test-only injection seam (defaults to `null` in real app usage, which
  /// resolves via `AppDatabase.instance.database` at bootstrap — same
  /// production wiring `home_screen.dart` uses). Exists purely so this
  /// screen can be widget-tested against a fake `Database` the same way
  /// the other classification screens are (a real
  /// `sqflite_common_ffi` `Database` hangs indefinitely inside
  /// `testWidgets` in this environment) without the real app's route
  /// table ever needing to pass one.
  final Database? db;

  @override
  State<ManageClassificationsScreen> createState() => _ManageClassificationsScreenState();
}

class _ManageClassificationsScreenState extends State<ManageClassificationsScreen> {
  Database? _db;
  final _newNameController = TextEditingController();

  bool _loadingGroups = true;
  List<ClassificationGroup> _groups = const [];
  ClassificationGroup? _selectedGroup;

  bool _loadingLists = false;
  List<ClassificationItem> _active = const [];
  List<ClassificationItem> _inactive = const [];

  bool _creating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    _db = db;
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await ClassificationDao.fetchGroups(_db!);
    if (!mounted) return;
    // Default selection: first enabled group in the fetched (id-ordered)
    // list — same data-driven convention T7 established, never a
    // hardcoded group code/index.
    ClassificationGroup? defaultGroup;
    for (final g in groups) {
      if (g.enabled) {
        defaultGroup = g;
        break;
      }
    }
    setState(() {
      _groups = groups;
      _selectedGroup = defaultGroup;
      _loadingGroups = false;
    });
    if (defaultGroup != null) {
      await _loadLists(defaultGroup);
    }
  }

  Future<void> _loadLists(ClassificationGroup group) async {
    setState(() {
      _loadingLists = true;
      _createError = null;
    });
    final active = await ClassificationDao.fetchActiveClassifications(_db!, groupId: group.id);
    final inactive = await ClassificationDao.fetchInactiveClassifications(_db!, groupId: group.id);
    if (!mounted) return;
    setState(() {
      _active = active;
      _inactive = inactive;
      _loadingLists = false;
    });
  }

  void _selectGroup(ClassificationGroup group) {
    // A disabled group (Pochi) never gets a tap handler attached in
    // _buildTabs below — this early return is a defensive second layer,
    // matching T7's own convention, not the actual enforcement mechanism
    // (the DB triggers are).
    if (!group.enabled) return;
    if (_selectedGroup?.id == group.id) return;
    _newNameController.clear();
    setState(() => _selectedGroup = group);
    _loadLists(group);
  }

  Future<void> _createClassification() async {
    final group = _selectedGroup;
    final name = _newNameController.text.trim();
    if (group == null || name.isEmpty) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      await ClassificationDao.createClassification(_db!, groupId: group.id, name: name);
      _newNameController.clear();
      await _loadLists(group);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _createError = e.isUniqueConstraintError()
            ? 'A classification named "$name" already exists in ${group.displayName}.'
            : 'Could not create classification: $e';
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _renameClassification(ClassificationItem item) async {
    final group = _selectedGroup;
    if (group == null) return;
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename classification'),
        content: TextField(
          controller: controller,
          maxLength: classificationNameMaxLength,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || newName == null || newName.isEmpty || newName == item.name) return;
    try {
      await ClassificationDao.renameClassification(_db!, id: item.id, newName: newName);
      await _loadLists(group);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      final msg = e.isUniqueConstraintError()
          ? 'A classification named "$newName" already exists in ${group.displayName}.'
          : 'Could not rename: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmDelete(ClassificationItem item) async {
    final group = _selectedGroup;
    if (group == null) return;
    final count = await ClassificationDao.countTransactionsForClassification(
      _db!,
      classificationId: item.id,
    );
    if (!mounted) return;
    // The delete confirmation shows a real
    // COUNT(*)-by-classification message, never a generic "are you sure".
    final message = count == 0
        ? 'No transactions currently use "${item.name}". '
            'It will be hidden, not deleted, and can be restored later.'
        : '$count transaction${count == 1 ? '' : 's'} use "${item.name}". '
            'It will be hidden, not deleted, and can be restored later.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete classification?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ClassificationDao.softDeleteClassification(_db!, id: item.id);
    await _loadLists(group);
  }

  Future<void> _restoreClassification(ClassificationItem item) async {
    final group = _selectedGroup;
    if (group == null) return;
    try {
      await ClassificationDao.restoreClassification(_db!, id: item.id);
      await _loadLists(group);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      // Genuine edge case: restoring into a group that meanwhile gained a
      // different active classification of the same name. See FLAGS.
      final msg = e.isUniqueConstraintError()
          ? 'Cannot restore — a classification named "${item.name}" already exists in ${group.displayName}.'
          : 'Could not restore: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Manage Classifications',
      followPalette: true,
      body: _loadingGroups
          ? Center(child: CircularProgressIndicator(color: palette.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _buildTabs(palette),
                const SizedBox(height: 14),
                if (_loadingLists)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: palette.primary)),
                  )
                else ...[
                  _buildCreateRow(palette),
                  const SizedBox(height: 18),
                  _SectionLabel('Active', palette: palette),
                  _buildActiveList(palette),
                  const SizedBox(height: 22),
                  _SectionLabel('Inactive (deleted)', palette: palette),
                  _buildInactiveList(palette),
                ],
              ],
            ),
    );
  }

  Widget _buildTabs(AppPalette palette) {
    return Row(
      children: [
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _ManageGroupTab(
              group: _groups[i],
              selected: _selectedGroup?.id == _groups[i].id,
              palette: palette,
              onTap: () => _selectGroup(_groups[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCreateRow(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newNameController,
                maxLength: classificationNameMaxLength,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                enabled: _selectedGroup != null && !_creating,
                style: TextStyle(color: palette.ink),
                cursorColor: palette.primary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New classification name',
                  hintStyle: TextStyle(color: palette.mutedInk),
                  border: OutlineInputBorder(borderSide: BorderSide(color: palette.line)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.line)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _createClassification(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_selectedGroup == null || _creating) ? null : _createClassification,
              style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
              child: _creating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary),
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
              style: TextStyle(fontSize: 12, color: palette.diffUp),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveList(AppPalette palette) {
    if (_active.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No active classifications in this group.',
          style: TextStyle(fontSize: 12.5, color: palette.mutedInk),
        ),
      );
    }
    return _card(
      palette,
      Column(
        children: [
          for (var i = 0; i < _active.length; i++)
            _ClassificationRow(
              name: _active[i].name,
              showDivider: i != _active.length - 1,
              palette: palette,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined, size: 19, color: palette.mutedInk),
                    tooltip: 'Rename',
                    onPressed: () => _renameClassification(_active[i]),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 19, color: palette.diffUp),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(_active[i]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInactiveList(AppPalette palette) {
    if (_inactive.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No inactive classifications in this group.',
          style: TextStyle(fontSize: 12.5, color: palette.mutedInk),
        ),
      );
    }
    return _card(
      palette,
      Column(
        children: [
          for (var i = 0; i < _inactive.length; i++)
            _ClassificationRow(
              name: _inactive[i].name,
              muted: true,
              showDivider: i != _inactive.length - 1,
              palette: palette,
              trailing: TextButton.icon(
                onPressed: () => _restoreClassification(_inactive[i]),
                style: TextButton.styleFrom(foregroundColor: palette.primary),
                icon: const Icon(Icons.restore, size: 17),
                label: const Text('Restore'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(AppPalette palette, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)), // Profile's own card radius (T24)
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: palette.mutedInk,
        ),
      ),
    );
  }
}

/// Locally-duplicated group-tab visual, matching T7's `_GroupTab` styling
/// (disabled-tab
/// opacity/no-pointer-events reused for Pochi, purely data-driven off
/// `group.enabled`, zero `POCHI_LA_BIASHARA` special-case code) — see this
/// file's class doc / FLAGS for why this isn't imported from T7's file
/// directly. T26: the unselected tab sits on [AppPalette.track], the same
/// "pill group on a track" language Analytics' `_BreakdownSwitch` uses.
class _ManageGroupTab extends StatelessWidget {
  const _ManageGroupTab({required this.group, required this.selected, required this.palette, required this.onTap});

  final ClassificationGroup group;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !group.enabled;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected && !disabled ? palette.primary : palette.track,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          alignment: Alignment.center,
          child: Text(
            disabled ? '${group.displayName} (n/a)' : group.displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected && !disabled ? palette.onPrimary : palette.mutedInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassificationRow extends StatelessWidget {
  const _ClassificationRow({
    required this.name,
    required this.showDivider,
    required this.trailing,
    required this.palette,
    this.muted = false,
  });

  final String name;
  final bool showDivider;
  final Widget trailing;
  final AppPalette palette;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: showDivider ? BoxDecoration(border: Border(bottom: BorderSide(color: palette.line))) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                color: muted ? palette.mutedInk : palette.ink,
                decoration: muted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
