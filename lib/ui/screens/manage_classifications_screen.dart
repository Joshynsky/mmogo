import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/app_database.dart';
import '../../data/db/classification_dao.dart';
import '../shell/secondary_scaffold.dart';
import '../theme/app_colors.dart';
import '../widgets/error_notes.dart';
import '../widgets/palette_alert_dialog.dart';

/// R31: the one sentence that ends the Delete category dialog (in use or not).
const kDeleteCategoryTail = 'It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.';

/// Group codes whose built-in category is locked and that have no create row.
const Set<String> manageLockedGroupCodes = {'AGENT_WITHDRAWAL', 'AIRTIME'};

/// Manage categories (T8, reworked to the signed M13 mock in 0.1.2 S8c-3 / MC1).
/// Own dedicated page (secondary chrome tier), reached from Settings: one tab
/// per group (six: Send Money, Paybill, Buy Goods, Pochi, Withdrawal, Airtime,
/// none hidden or dimmed), an active list and a separate inactive (deleted)
/// list per group, create / rename / soft-delete (with a real
/// `COUNT(*)`-by-category delete confirmation) and restore.
///
/// Withdrawal and Airtime each have one built-in category: it is locked (tag
/// "Built in", no Rename, no Delete) and the group has no create row; a muted
/// line says so. The other four groups keep the create row. Errors are error
/// pattern A (red text with the warning icon, no timer): a name that already
/// exists (create, rename) and a blocked restore. The Cash picker is a separate
/// flat list of ids 1 to 6 and is not changed here.
///
/// Follows the chosen palette (`SecondaryScaffold(followPalette: true)`).
class ManageClassificationsScreen extends StatefulWidget {
  const ManageClassificationsScreen({super.key, this.db});

  /// Test-only injection seam (defaults to `null` in real app usage, which
  /// resolves via `AppDatabase.instance.database` at bootstrap). A real
  /// `sqflite_common_ffi` `Database` hangs inside `testWidgets` in this
  /// environment, so widget tests pass a fake.
  final Database? db;

  @override
  State<ManageClassificationsScreen> createState() => _ManageClassificationsScreenState();
}

class _ManageClassificationsScreenState extends State<ManageClassificationsScreen> {
  Database? _db;
  final _newNameController = TextEditingController();
  final Map<int, GlobalKey> _tabKeys = {};

  bool _loadingGroups = true;
  List<ClassificationGroup> _groups = const [];
  ClassificationGroup? _selectedGroup;

  bool _loadingLists = false;
  List<ClassificationItem> _active = const [];
  List<ClassificationItem> _inactive = const [];

  bool _creating = false;
  String? _createError;
  String? _restoreError;

  bool get _locked => manageLockedGroupCodes.contains(_selectedGroup?.code);

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
    // Default selection: the first enabled group in the fetched (id-ordered)
    // list, never a hardcoded group code or index.
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
    setState(() => _loadingLists = true);
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
    if (!group.enabled) return; // the DB triggers are the real enforcement
    if (_selectedGroup?.id == group.id) return;
    _newNameController.clear();
    setState(() {
      _selectedGroup = group;
      _createError = null;
      _restoreError = null;
    });
    _loadLists(group);
    // The chosen tab slides into view (the row scrolls sideways).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[group.id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 200));
      }
    });
  }

  String _dupText(String name, ClassificationGroup group) =>
      'A category named "$name" already exists in ${group.displayName}.';

  Future<void> _createClassification() async {
    final group = _selectedGroup;
    final name = _newNameController.text.trim();
    if (group == null || name.isEmpty || manageLockedGroupCodes.contains(group.code)) return;
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
        _createError = e.isUniqueConstraintError() ? _dupText(name, group) : 'Could not create the category.';
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _renameClassification(ClassificationItem item) async {
    final group = _selectedGroup;
    if (group == null || manageLockedGroupCodes.contains(group.code)) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RenameDialog(
        initial: item.name,
        onSave: (newName) async {
          if (newName.isEmpty) return 'Enter a name.';
          if (newName == item.name) return null;
          try {
            await ClassificationDao.renameClassification(_db!, id: item.id, newName: newName);
          } on DatabaseException catch (e) {
            return e.isUniqueConstraintError() ? _dupText(newName, group) : 'Could not rename the category.';
          }
          return null;
        },
      ),
    );
    if (!mounted || saved != true) return;
    await _loadLists(group);
  }

  Future<void> _confirmDelete(ClassificationItem item) async {
    final group = _selectedGroup;
    if (group == null || manageLockedGroupCodes.contains(group.code)) return;
    final count = await ClassificationDao.countTransactionsForClassification(
      _db!,
      classificationId: item.id,
    );
    if (!mounted) return;
    // The delete confirmation shows a real COUNT(*)-by-category message,
    // never a generic "are you sure".
    final message = count == 0
        ? 'No transactions currently use "${item.name}". $kDeleteCategoryTail'
        : '$count transaction${count == 1 ? '' : 's'} use "${item.name}". $kDeleteCategoryTail';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => PaletteAlertDialog(
        title: const Text('Delete category?'),
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
      if (mounted) setState(() => _restoreError = null);
      await _loadLists(group);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      // Restoring into a group that meanwhile gained an active category of
      // the same name: an inline error beside the list (pattern A), no snackbar.
      setState(() {
        _restoreError = e.isUniqueConstraintError()
            ? 'Can’t restore: a category named "${item.name}" already exists in ${group.displayName}.'
            : 'Could not restore the category.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Manage categories',
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
                  if (_locked) _buildLockedLine(palette) else _buildCreateRow(palette),
                  const SizedBox(height: 18),
                  _SectionLabel('Active', palette: palette),
                  _buildActiveList(palette),
                  const SizedBox(height: 22),
                  _SectionLabel('Inactive (deleted)', palette: palette),
                  if (_restoreError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FieldError(
                        _restoreError!,
                        key: const Key('manageRestoreError'),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                    ),
                  _buildInactiveList(palette),
                ],
              ],
            ),
    );
  }

  /// Six tabs in one sideways-scrolling row, none dimmed (the mock's `.mtabs`).
  Widget _buildTabs(AppPalette palette) {
    return SingleChildScrollView(
      key: const Key('manageTabs'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _groups.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _ManageGroupTab(
              key: _tabKeys.putIfAbsent(_groups[i].id, GlobalKey.new),
              group: _groups[i],
              selected: _selectedGroup?.id == _groups[i].id,
              palette: palette,
              onTap: () => _selectGroup(_groups[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLockedLine(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '${_selectedGroup!.displayName} entries always use this category.',
        key: const Key('manageLockedLine'),
        style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: palette.mutedInk),
      ),
    );
  }

  Widget _buildCreateRow(AppPalette palette) {
    final hasError = _createError != null;
    final borderColor = hasError ? palette.error : palette.line;
    return Column(
      key: const Key('manageCreateRow'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('manageCreateField'),
                controller: _newNameController,
                maxLength: classificationNameMaxLength,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                enabled: _selectedGroup != null && !_creating,
                style: TextStyle(color: palette.ink),
                cursorColor: palette.primary,
                onChanged: (_) {
                  if (_createError != null) setState(() => _createError = null);
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New category name',
                  hintStyle: TextStyle(color: palette.mutedInk),
                  border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1)),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: hasError ? palette.error : palette.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                onSubmitted: (_) => _createClassification(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('manageCreateAdd'),
              onPressed: (_selectedGroup == null || _creating) ? null : _createClassification,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                minimumSize: const Size(64, 44),
              ),
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
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FieldError(
              _createError!,
              key: const Key('manageCreateError'),
              padding: const EdgeInsets.symmetric(horizontal: 2),
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
          'No active categories in this group.',
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
              trailing: _locked
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        key: Key('manageBuiltIn-${_active[i].name}'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          'Built in',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: palette.mutedInk,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 19, color: palette.mutedInk),
                          tooltip: 'Rename ${_active[i].name}',
                          onPressed: () => _renameClassification(_active[i]),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 19, color: palette.diffUp),
                          tooltip: 'Delete ${_active[i].name}',
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
          'No inactive categories in this group.',
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

/// The Rename dialog: stays open on a failed save and shows the error inline
/// (pattern A) under the field until the user types again.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.onSave});

  final String initial;

  /// Returns an error text, or null when the rename was saved.
  final Future<String?> Function(String newName) onSave;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = await widget.onSave(_controller.text.trim());
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PaletteAlertDialog(
      title: const Text('Rename category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('manageRenameField'),
            controller: _controller,
            maxLength: classificationNameMaxLength,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            autofocus: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(borderSide: BorderSide(color: _error != null ? palette.error : palette.line)),
            ),
          ),
          if (_error != null)
            FieldError(_error!, key: const Key('manageRenameError'), padding: const EdgeInsets.only(top: 6)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
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

/// One group tab: a 44 dp pill (the unselected tab sits on [AppPalette.track]).
/// Never dimmed: all six groups are usable (MC1 replaced the "(n/a)" style).
class _ManageGroupTab extends StatelessWidget {
  const _ManageGroupTab({
    super.key,
    required this.group,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ClassificationGroup group;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('manageTab-${group.code}'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? palette.primary : palette.track,
            borderRadius: const BorderRadius.all(Radius.circular(22)),
          ),
          alignment: Alignment.center,
          child: Text(
            group.displayName,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? palette.onPrimary : palette.mutedInk,
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
