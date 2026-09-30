import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../app_info.dart';
import '../../data/db/app_database.dart';
import '../../data/db/local_data_summary_dao.dart';
import '../../data/prefs/app_prefs.dart';
import '../../domain/format/byte_size.dart';
import '../../domain/format/money.dart';
import '../shell/secondary_scaffold.dart';
import '../theme/app_colors.dart';

/// Secondary page 1 of 3 (two-tier chrome: back-arrow + mini-FAB via
/// [SecondaryScaffold], not the full bottom nav) — T17, following the validated earlier prototype (used as a
/// behavior/layout reference only). Three cards:
///   1. App info — name + version from [AppInfo] (a Dart constant kept in
///      sync with `pubspec.yaml` by a test; no new plugin).
///   2. "How Home greets you" — editable display name (max 30 chars,
///      trimmed, empty clears the key) written via
///      [AppPrefs.writeUserDisplayName], which also notifies a live Home.
///   3. Local data summary — aggregates only ([LocalDataSummaryDao]):
///      transactions stored, date range covered, storage used (est.).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.db});

  /// Test-only injection seam (`null` in real app usage resolves via
  /// `AppDatabase.instance.database`) — same convention
  /// `settings_screen.dart`/`recently_deleted_screen.dart` already use,
  /// since a real `sqflite_common_ffi` `Database` hangs inside `testWidgets`
  /// in this environment.
  final Database? db;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _nameEdited = false;
  bool _saving = false;

  // `null` until loaded — rendered as "—", the prototype's own pre-load
  // placeholder. Deliberately no spinner: the name card must be usable
  // immediately, independent of the database load.
  LocalDataSummary? _summary;
  int? _storageBytes;
  bool _summaryLoaded = false;

  @override
  void initState() {
    super.initState();
    // Independent loads: the name field must never wait on the database.
    _loadName();
    _loadSummary();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final name = await AppPrefs.readUserDisplayName();
    // Don't clobber anything the user already started typing.
    if (!mounted || _nameEdited || name == null) return;
    _nameController.text = name;
  }

  Future<void> _loadSummary() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    if (!mounted) return;
    final summary = await LocalDataSummaryDao.summary(db);
    final bytes = await LocalDataSummaryDao.databaseFileSizeBytes(db);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _storageBytes = bytes;
      _summaryLoaded = true;
    });
  }

  Future<void> _saveName() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final trimmed = _nameController.text.trim();
    final ok = await AppPrefs.writeUserDisplayName(trimmed);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _nameController.text = trimmed;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? 'Couldn\'t save your name — please try again'
              : trimmed.isEmpty
                  ? 'Name cleared — Home will greet you without a name'
                  : 'Saved — Home will greet you as $trimmed',
        ),
      ),
    );
  }

  String get _countText {
    final s = _summary;
    if (s == null) return '—';
    return '${s.transactionCount} transaction${s.transactionCount == 1 ? '' : 's'}';
  }

  String get _rangeText {
    final s = _summary;
    if (s == null) return '—';
    if (s.isEmpty || s.earliestOccurredAt == null || s.latestOccurredAt == null) {
      return 'No data yet';
    }
    return '${formatLongDate(s.earliestOccurredAt!)} – ${formatLongDate(s.latestOccurredAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Profile',
      followPalette: true,
      body: ListView(
        // Extra bottom padding keeps the last card clear of the mini-FAB.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          _Card(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                  ),
                  child: Icon(Icons.account_balance_wallet_outlined, color: palette.onPrimary, size: 28),
                ),
                Text(
                  AppInfo.name,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  AppInfo.displayVersion,
                  style: TextStyle(fontSize: 12.5, color: palette.mutedInk),
                ),
              ],
            ),
          ),
          _Card(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardLabel('How Home greets you', palette: palette),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('profile-name-field'),
                        controller: _nameController,
                        maxLength: AppPrefs.userDisplayNameMaxLength,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => _nameEdited = true,
                        onSubmitted: (_) => _saveName(),
                        style: TextStyle(fontSize: 14, color: palette.ink),
                        cursorColor: palette.primary,
                        decoration: InputDecoration(
                          hintText: 'Your name (optional)',
                          hintStyle: TextStyle(color: palette.mutedInk),
                          isDense: true,
                          counterText: '',
                          filled: true,
                          fillColor: palette.brightness == Brightness.dark ? palette.tint : palette.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: palette.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: palette.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: palette.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _saveName,
                      style: TextButton.styleFrom(foregroundColor: palette.primary),
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Card(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardLabel('Local data summary', palette: palette),
                _SummaryRow(label: 'Transactions stored', value: _countText, palette: palette),
                _SummaryRow(label: 'Date range covered', value: _rangeText, palette: palette),
                _SummaryRow(
                  label: 'Storage used (est.)',
                  value: _summaryLoaded ? formatByteSize(_storageBytes) : '—',
                  palette: palette,
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: palette.mutedInk,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, required this.palette, this.last = false});

  final String label;
  final String value;
  final AppPalette palette;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}
