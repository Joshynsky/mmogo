import 'package:flutter/material.dart';

import '../../../data/backup/auto_backup_leftovers.dart';
import '../../copy/backup_copy.dart';
import '../../copy/delete_data_copy.dart' show kDataOpBusy;
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';
import 'backup_sheet_shell.dart';

/// §SCREEN.BACKUP.LEFTOVER — 0.1.2 S10b (LF1, A4b, CB9). ONE sheet for what
/// happens when the user stops using a backup folder:
///  - the leftover question (only when the old folder holds automatic backup
///    files): radio cards, KEEP is the default, Delete needs the explicit
///    choice and its button turns red and says how many files;
///  - the old-folder question (only on Choose folder, never on switch-off):
///    "Stop using it" (release the permission, the default and the initial
///    focus) or "Keep access". This same-sheet question IS the grant-release
///    confirm (A4b): the explanation is on screen with the pair before
///    Continue, and no second dialog follows.
/// Outside tap, Back and a swipe down are [LeftoverDecision.cancel] (keep the
/// files, keep the permission); the folder change itself still goes on.
/// Never a file name, a URI or a folder name: a count and a date range only.

Future<LeftoverDecision> showLeftoverSheet(BuildContext context, LeftoverPrompt prompt) async {
  final palette = AppPalette.of(context);
  final d = await showBackupSheet<LeftoverDecision>(context, (_) => LeftoverSheet(palette: palette, prompt: prompt));
  return d ?? LeftoverDecision.cancel;
}

class LeftoverSheet extends StatefulWidget {
  const LeftoverSheet({super.key, required this.palette, required this.prompt});

  final AppPalette palette;
  final LeftoverPrompt prompt;

  @override
  State<LeftoverSheet> createState() => _LeftoverSheetState();
}

class _LeftoverSheetState extends State<LeftoverSheet> {
  LeftoverChoice _leftover = LeftoverChoice.keep;
  GrantChoice _grant = GrantChoice.release;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final prompt = widget.prompt;
    final scan = prompt.leftovers;
    final n = scan?.count ?? 0;
    final del = scan != null && _leftover == LeftoverChoice.delete;
    final title = scan != null ? kLeftoverTitle : kOldFolderTitle;
    final label = scan == null ? kContinue : (del ? leftoverDeleteLabel(n) : leftoverContinueKeep(n));
    return BackupSheetShell(
      palette: p,
      title: title,
      body: [
        if (scan != null) ...[
          Text(
            leftoverBody(n, scan.oldest, scan.newest),
            key: const Key('leftoverBody'),
            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
          ),
          Text(kLeftoverCountedNote, style: TextStyle(fontSize: 12, color: p.mutedInk)),
          Semantics(
            container: true,
            label: kLeftoverWhatToDo,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RadioCard(
                  key: const Key('leftoverKeep'),
                  palette: p,
                  label: leftoverKeepLabel(n),
                  selected: _leftover == LeftoverChoice.keep,
                  red: false,
                  onTap: () => setState(() => _leftover = LeftoverChoice.keep),
                ),
                const SizedBox(height: 8),
                _RadioCard(
                  key: const Key('leftoverDelete'),
                  palette: p,
                  label: leftoverDeleteLabel(n),
                  selected: del,
                  red: true,
                  onTap: () => setState(() => _leftover = LeftoverChoice.delete),
                ),
              ],
            ),
          ),
        ],
        if (prompt.askGrant) ...[
          if (scan != null) Divider(height: 1, color: p.line),
          if (scan != null)
            Semantics(
              header: true,
              child: Text(
                kOldFolderTitle,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
              ),
            ),
          Text(
            kOldFolderBody,
            key: const Key('oldFolderBody'),
            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
          ),
          Semantics(
            container: true,
            label: kOldFolderGroup,
            child: Row(
              children: [
                Expanded(
                  child: _PairButton(
                    key: const Key('grantRelease'),
                    palette: p,
                    label: kStopUsingIt,
                    selected: _grant == GrantChoice.release,
                    autofocus: true,
                    onTap: () => setState(() => _grant = GrantChoice.release),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PairButton(
                    key: const Key('grantKeep'),
                    palette: p,
                    label: kKeepAccess,
                    selected: _grant == GrantChoice.keepAccess,
                    onTap: () => setState(() => _grant = GrantChoice.keepAccess),
                  ),
                ),
              ],
            ),
          ),
          Text(kKeepAccessHint, style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk)),
        ],
      ],
      actions: FilledButton(
        key: const Key('leftoverContinue'),
        // With the old-folder pair on the sheet the focus starts on "Stop
        // using it"; without it (switch-off) it starts here.
        autofocus: !prompt.askGrant,
        onPressed: () => Navigator.of(context).pop(
          LeftoverDecision(
            leftover: _leftover,
            // Switch-off has no grant field; the service ignores it there.
            grant: prompt.askGrant ? _grant : GrantChoice.keepAccess,
          ),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          backgroundColor: del ? p.diffUp : p.primary,
          foregroundColor: del ? p.onDelete : p.onPrimary,
        ),
        child: Text(label),
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.red,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final bool selected;
  final bool red;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = red ? palette.diffUp : palette.primary;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? accent : palette.line, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? accent : palette.mutedInk,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.ink)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PairButton extends StatelessWidget {
  const _PairButton({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final AppPalette palette;
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: selected
          ? FilledButton(
              autofocus: autofocus,
              onPressed: onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                shape: const StadiumBorder(),
              ),
              child: Text(label, textAlign: TextAlign.center),
            )
          : OutlinedButton(
              autofocus: autofocus,
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.line, width: 1.5),
                shape: const StadiumBorder(),
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
    );
  }
}

/// The text of the toast that follows a folder change or switch-off, or null
/// for none (A11): "Kept 6 files." / "Deleted 6 files." /
/// "Deleted 4. 2 could not be deleted." (also when 0 were deleted); nothing
/// when no question was asked, when the listing failed, or when only the
/// old-folder question was asked. Busy says so.
String? folderChangeToast(FolderChangeResult r) {
  if (r.busy) return kDataOpBusy;
  final d = r.deleted;
  if (d != null) {
    if (d.listingFailed) return null;
    return d.failed > 0 ? deletedPartlyToast(d.deleted, d.failed) : deletedToast(d.deleted);
  }
  return r.kept > 0 ? keptToast(r.kept) : null;
}

/// The non-dismissible "Working..." sheet shown while a folder change, a
/// switch-off or a leftover delete runs (A11). Back, a tap outside and a swipe
/// do nothing. [show] and [hide] may be called in turn (the question sheet is
/// shown between two stretches of work).
class FolderWorking {
  FolderWorking(this._context);

  final BuildContext _context;
  NavigatorState? _nav;
  bool _open = false;
  int _gen = 0;

  bool get isOpen => _open;

  void show() {
    if (_open || !_context.mounted) return;
    _open = true;
    final gen = ++_gen;
    _nav = Navigator.of(_context);
    final palette = AppPalette.of(_context);
    showBackupSheet<void>(
      _context,
      (_) => PopScope(canPop: false, child: _WorkingSheet(palette: palette)),
      dismissible: false,
    ).whenComplete(() {
      // An older sheet finishing must not close the state of a newer one.
      if (_gen == gen) _open = false;
    });
  }

  void hide() {
    if (!_open) return;
    _open = false;
    _nav?.pop();
  }
}

class _WorkingSheet extends StatelessWidget {
  const _WorkingSheet({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return BackupSheetShell(
      palette: palette,
      title: kFolderWorking,
      body: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  kFolderWorking,
                  key: const Key('folderWorking'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
