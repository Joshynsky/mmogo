import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../app_info.dart';
import '../../data/db/app_database.dart';
import '../../data/db/export_dao.dart';
import '../../data/prefs/app_prefs.dart';
import '../shell/primary_scaffold.dart';
import '../shell/primary_shell.dart';
import '../shell/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette_scope.dart';
import '../widgets/coach_tour.dart';

/// Settings' coach-tour page id (the seen flag is `tour_seen_settings`).
const settingsTourId = 'settings';

/// Primary destination 5 of 5. T2's original routing scope for this screen:
/// the two links that hand off to secondary pages (Manage Classifications,
/// Recently Deleted) and back. T8 wired the "Manage Classifications" link to
/// its real page. T10 wired "Export CSV" to the real `ExportDao` query +
/// `share_plus` share sheet (CSV export has no table of its own). T18 wired the "Auto-recognize classifications" toggle to
/// `AppPrefs`' real read/write pair. T23 (this dispatch) reworks the page
/// to the T23 draft mock: seamless top bar, followPhoneTheme, cards
/// regrouped under Appearance/Your data/Preferences, and a working colour
/// palette switch (`AppPaletteScope`) at the top — palette tokens only, no
/// `AppColors.muted`/`text` on this page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.db, this.exportCsv});

  /// Test-only injection seam (defaults to `null` in real app usage, which
  /// resolves via `AppDatabase.instance.database` at bootstrap — same
  /// convention `manage_classifications_screen.dart`/
  /// `recently_deleted_screen.dart` already use). A real
  /// `sqflite_common_ffi` `Database` hangs indefinitely inside
  /// `testWidgets` in this environment, so widget tests drive this screen
  /// against a fake `Database` instead.
  final Database? db;

  /// Test-only injection seam for the write-temp-file + `share_plus`
  /// share-sheet side effect ([_defaultExportCsv]). `null` in real app
  /// usage resolves to the real implementation, which touches
  /// `path_provider`/`share_plus` platform channels not available inside
  /// `testWidgets` in this environment — widget tests inject a fake here to
  /// exercise the button's enabled/disabled state and success/failure
  /// SnackBar without a real platform channel, while `export_dao_test.dart`
  /// separately, authoritatively proves the real CSV content/row-count
  /// against a genuine in-memory sqlite3 database.
  final Future<void> Function(String csvContent, int transactionCount)? exportCsv;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with PrimaryTabRefresh<SettingsScreen> {
  Database? _db;
  bool _loading = true;
  int _activeCount = 0;
  bool _exporting = false;
  // Sane default while `_loading` is true: matches AppPrefs' own
  // documented default (ON) so the switch doesn't visibly flip from
  // off->on once the real read resolves in the common case.
  bool _autoRecognize = true;

  // Coach-tour anchors.
  final _paletteTourKey = GlobalKey();
  final _dataTourKey = GlobalKey();
  final _prefsTourKey = GlobalKey();
  bool _tourOffered = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // F5: back on the Settings tab, re-read the count and the switch.
  @override
  int get primaryTabIndex => 4;

  @override
  void onPrimaryTabShown() {
    _bootstrap();
    // Back after the tour paused (system Back, another tab): pick it up.
    if (_tourOffered && primaryShell?.index.value == primaryTabIndex) _offerTour();
  }

  /// Shows the tour (or its unfinished rest) once the frame has painted.
  void _offerTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: settingsTourId, steps: _tourSteps());
    });
  }

  Future<void> _bootstrap() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    if (!mounted) return;
    final count = await ExportDao.activeTransactionCount(db);
    final autoRecognize = await AppPrefs.readAutoRecognizeClassifications();
    if (!mounted) return;
    setState(() {
      _db = db;
      _activeCount = count;
      _autoRecognize = autoRecognize;
      _loading = false;
    });
    if (!_tourOffered) {
      _tourOffered = true;
      _offerTour();
    }
  }

  /// Flips the switch immediately (never waits on the write) then persists
  /// in the background — same "update local state now, persist
  /// fire-and-forget" shape as [_handleExport]'s SnackBar-on-completion
  /// pattern, but without a SnackBar: a `Switch` gives its own instant
  /// visual feedback, so no extra confirmation UI is needed here.
  void _handleAutoRecognizeChanged(bool value) {
    setState(() => _autoRecognize = value);
    AppPrefs.writeAutoRecognizeClassifications(value);
  }

  /// Real (non-test) share-sheet implementation: writes the CSV to a temp
  /// file (needed because `share_plus`'s `ShareParams.files` wraps
  /// `Intent.ACTION_SEND` with a file attachment, not raw text) then hands
  /// it to the OS share sheet (the settled mechanism for export).
  static Future<void> _defaultExportCsv(String csvContent, int transactionCount) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'mymog-export-${DateTime.now().millisecondsSinceEpoch}.csv';
    final path = p.join(dir.path, fileName);
    await File(path).writeAsString(csvContent);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'text/csv', name: fileName)],
        subject: 'My Money Goes CSV export',
      ),
    );
  }

  Future<void> _handleExport() async {
    final db = _db;
    if (db == null || _activeCount == 0 || _exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = await ExportDao.activeTransactions(db);
      final csv = ExportDao.toCsv(rows);
      final exportFn = widget.exportCsv ?? _defaultExportCsv;
      await exportFn(csv, rows.length);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV exported — ${rows.length} transaction${rows.length == 1 ? '' : 's'}'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV export failed — please try again')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Clears every page's "tour seen" flag. Pages already open in this session
  /// offer their tour again next launch (Add: next time it is opened); their
  /// header "?" replays one straight away.
  Future<void> _showTipsAgain() async {
    await AppPrefs.resetAllTours();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tips reset. The guides will show again.')),
    );
  }

  List<CoachStep> _tourSteps() => [
    CoachStep(target: _paletteTourKey, text: 'Pick a colour palette. It follows your phone’s light or dark mode.'),
    CoachStep(
      target: _dataTourKey,
      text: 'Manage your categories, restore deleted transactions, or share everything as a CSV.',
      onEnter: () => scrollIntoView(_dataTourKey),
      actionLabel: 'Open Manage classifications',
      onAction: () async {
        // The tour pauses here; when Manage classifications is closed, pick
        // it up at the next step.
        await Navigator.of(context).pushNamed(Routes.manageClassifications);
        if (mounted) {
          CoachTour.maybeStart(context, pageId: settingsTourId, steps: _tourSteps());
        }
      },
    ),
    CoachStep(
      target: _prefsTourKey,
      text: 'Suggest categories for repeat receivers. “Show tips again” replays these guides.',
      onEnter: () => scrollIntoView(_prefsTourKey),
    ),
  ];

  void _replayTour() => CoachTour.start(context, pageId: settingsTourId, steps: _tourSteps());

  String get _exportSubtitle {
    if (_loading) return 'Loading…';
    if (_activeCount == 0) return 'No transactions to export yet';
    if (_exporting) return 'Preparing export…';
    return 'Share all $_activeCount transaction${_activeCount == 1 ? '' : 's'} as CSV';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final exportEnabled = !_loading && _activeCount > 0 && !_exporting;
    return PrimaryScaffold(
      title: 'Settings',
      activeIndex: 4,
      followPhoneTheme: true,
      onHelp: _loading ? null : _replayTour,
      // No pull-to-refresh on Settings (PM direct decision, T23 draft):
      // nothing here changes from elapsed time the way Home/Analytics do.
      body: ListView(
        key: const Key('settingsScroll'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          _SectionLabel('Appearance', palette: palette),
          KeyedSubtree(
            key: _paletteTourKey,
            child: _SettingsCard(
              palette: palette,
              child: _PaletteGroup(
                currentPaletteId: AppPaletteScope.of(context).value,
                palette: palette,
                onSelect: (id) => AppPaletteScope.of(context).select(id),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Your data', palette: palette),
          KeyedSubtree(
            key: _dataTourKey,
            child: _SettingsCard(
              palette: palette,
              child: Column(
                children: [
                  _SettingsLink(
                    palette: palette,
                    icon: Icons.category_outlined,
                    label: 'Manage classifications',
                    subtitle: 'Create, rename, delete and restore',
                    first: true,
                    onTap: () => Navigator.of(context).pushNamed(Routes.manageClassifications),
                  ),
                  _SettingsLink(
                    palette: palette,
                    icon: Icons.restore_from_trash_outlined,
                    label: 'Recently deleted',
                    subtitle: 'Restore transactions you removed',
                    onTap: () => Navigator.of(context).pushNamed(Routes.recentlyDeleted),
                  ),
                  _SettingsLink(
                    palette: palette,
                    icon: Icons.ios_share,
                    label: 'Export CSV',
                    subtitle: _exportSubtitle,
                    onTap: exportEnabled ? _handleExport : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Preferences', palette: palette),
          KeyedSubtree(
            key: _prefsTourKey,
            child: _SettingsCard(
              palette: palette,
              child: Column(
                children: [
                  _SettingsToggle(
                    palette: palette,
                    icon: Icons.auto_awesome_outlined,
                    label: 'Auto-recognize classifications',
                    subtitle: 'Suggest a classification for repeat senders and receivers while you add',
                    first: true,
                    value: _autoRecognize,
                    onChanged: _loading ? null : _handleAutoRecognizeChanged,
                  ),
                  _SettingsLink(
                    palette: palette,
                    icon: Icons.lightbulb_outline,
                    label: 'Show tips again',
                    subtitle: 'Replay the guide on every page',
                    onTap: _showTipsAgain,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${AppInfo.name} ${AppInfo.versionName} · your data stays on this phone',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: palette.mutedInk),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: palette.mutedInk),
      ),
    );
  }
}

/// A rounded, palette-coloured card (mock `.acard`): the same shape Paid to
/// (T22) already uses for its own cards.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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

/// The "Colour palette" head + the 3-tile radio group (mock `.shead` +
/// `.palgrid`).
class _PaletteGroup extends StatelessWidget {
  const _PaletteGroup({required this.currentPaletteId, required this.palette, required this.onSelect});

  final String currentPaletteId;
  final AppPalette palette;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Colour palette', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
              const SizedBox(height: 3),
              Text(
                'Recolours the whole app. Light or dark follows your phone.',
                style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Semantics(
            container: true,
            label: 'Colour palette',
            child: Row(
              children: [
                for (final (i, set) in AppPalettes.all.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PaletteTile(
                      set: set,
                      brightness: palette.brightness,
                      accent: palette,
                      selected: set.id == currentPaletteId,
                      onTap: () => onSelect(set.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One palette radio tile (mock `.pal`): a mini preview (the primary strip
/// + page background + the 4 type-colour bars), the name, and a check on
/// the selected one. The preview always shows the OPTION's own colours at
/// the phone's current brightness; the selected border/check use the
/// currently ACTIVE palette's primary ([accent]), same as the mock's
/// `var(--primary)` (set by whichever palette is applied app-wide).
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.set,
    required this.brightness,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppPaletteSet set;
  final Brightness brightness;
  final AppPalette accent;
  final bool selected;
  final VoidCallback onTap;

  static const _barHeights = [0.70, 0.45, 0.30, 0.55];

  @override
  Widget build(BuildContext context) {
    final preview = set.forBrightness(brightness);
    final typeColors = [preview.typeSendMoney, preview.typePaybill, preview.typeBuyGoods, preview.typeCash];
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${set.name}${selected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Material(
        color: preview.background,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: InkWell(
          key: Key('paletteTile-${set.id}'),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(color: selected ? accent.primary : accent.line, width: 2),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(9)),
                      child: SizedBox(
                        height: 46,
                        child: Column(
                          children: [
                            Container(height: 14, color: preview.primary),
                            Expanded(
                              child: Container(
                                color: preview.background,
                                padding: const EdgeInsets.fromLTRB(5, 4, 5, 0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (final (i, c) in typeColors.indexed) ...[
                                      if (i > 0) const SizedBox(width: 3),
                                      Expanded(
                                        child: FractionallySizedBox(
                                          heightFactor: _barHeights[i],
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: c,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      set.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: preview.ink),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: accent.primary, shape: BoxShape.circle),
                      child: Icon(Icons.check, size: 12, color: accent.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.first = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              _RowIcon(icon: icon, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: palette.mutedInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// A `_SettingsLink`-shaped row for a boolean preference: same icon/label/
/// subtitle styling, but a trailing `Switch` (state the user toggles in
/// place) instead of a chevron.
class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.first = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              _RowIcon(icon: icon, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: palette.onPrimary,
                activeTrackColor: palette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rounded icon tile at the start of a settings row (mock `.srow .ic`).
class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.palette});

  final IconData icon;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.tint, borderRadius: const BorderRadius.all(Radius.circular(10))),
      child: Icon(icon, size: 18, color: palette.tintInk),
    );
  }
}
