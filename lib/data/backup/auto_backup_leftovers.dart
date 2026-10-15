// §DATA.AUTO_BACKUP.LEFTOVERS — 0.1.2 S10a (A4a, CB9, LF1). The types the
// auto-backup service uses to find and delete the automatic backup files left
// in a folder the user stops using, and to ask the user once. No file name,
// URI or folder name is ever carried: counts and dates only.

/// What to do with the automatic backups left in the old folder.
enum LeftoverChoice {
  /// Default. Leave the files where they are.
  keep,

  /// Delete the matching automatic files (never a manual backup).
  delete,
}

/// What to do with the permission mmogo holds on the old folder (asked only
/// when the user picks another folder, never on switch-off).
enum GrantChoice {
  /// Give the permission back.
  release,

  /// Default. Keep the permission.
  keepAccess,
}

/// The user's answer, asked ONCE. Every cancel path (Back, outside tap, a
/// thrown error, null) is [cancel]: keep the files and the permission, and the
/// folder change goes on.
class LeftoverDecision {
  const LeftoverDecision({required this.leftover, required this.grant});

  final LeftoverChoice leftover;
  final GrantChoice grant;

  static const LeftoverDecision cancel =
      LeftoverDecision(leftover: LeftoverChoice.keep, grant: GrantChoice.keepAccess);

  @override
  String toString() => 'LeftoverDecision(${leftover.name}, ${grant.name})';
}

/// Automatic backup files found in the freshly listed old folder: a file whose
/// whole name matches `AutoBackupService.autoFileName`. Counts and dates only.
class LeftoverScan {
  const LeftoverScan({required this.count, this.oldest, this.newest, this.writtenCount = 0});

  /// Matching files found.
  final int count;

  /// Dates in the file names (local time), oldest and newest.
  final DateTime? oldest;
  final DateTime? newest;

  /// How many files the app's own written list held when the question was
  /// built. Kept for the result; NOT used to decide what is a leftover.
  final int writtenCount;
}

/// The question the UI answers. [leftovers] is null when the old folder holds
/// no matching file (then only the permission question, if [askGrant], is
/// asked).
class LeftoverPrompt {
  const LeftoverPrompt({required this.leftovers, required this.askGrant, required this.switchingOff});

  final LeftoverScan? leftovers;

  /// True on Choose folder: the old-folder question (keep or release the
  /// permission). False on switch-off: leftovers only.
  final bool askGrant;
  final bool switchingOff;
}

/// The injected decision callback. Returning null, throwing, or completing with
/// [LeftoverDecision.cancel] all mean "keep everything".
typedef LeftoverDecider = Future<LeftoverDecision?> Function(LeftoverPrompt prompt);

/// What `deleteLeftovers` did. Counts and dates only.
class LeftoverDeleteResult {
  const LeftoverDeleteResult({
    this.deleted = 0,
    this.failed = 0,
    this.oldest,
    this.newest,
    this.listingFailed = false,
  });

  static const LeftoverDeleteResult none = LeftoverDeleteResult();

  final int deleted;
  final int failed;
  final DateTime? oldest;
  final DateTime? newest;

  /// The folder could not be listed at delete time: nothing was deleted.
  final bool listingFailed;

  int get attempted => deleted + failed;
}

/// What `changeFolder` / `switchOff` did, for the toasts ("Kept 6 files.",
/// "Deleted 6 files.", "Deleted 4. 2 could not be deleted.").
class FolderChangeResult {
  const FolderChangeResult({
    required this.ok,
    this.busy = false,
    this.asked = false,
    this.decision = LeftoverDecision.cancel,
    this.found = 0,
    this.deleted,
    this.grantReleased = false,
    this.listingFailed = false,
    this.writtenCount = 0,
  });

  /// All preferences were written (and nothing was busy).
  final bool ok;

  /// A background backup run could not be stopped in time, or another data
  /// operation holds the service: nothing was changed.
  final bool busy;

  /// The decision callback was asked.
  final bool asked;

  /// The answer used ([LeftoverDecision.cancel] when not asked).
  final LeftoverDecision decision;

  /// Matching automatic files found in the old folder (0 when not listed).
  final int found;

  /// Set when a delete was run.
  final LeftoverDeleteResult? deleted;

  /// The old folder's permission was given back.
  final bool grantReleased;

  /// The old folder could not be listed: no question was asked and the quiet
  /// release of today ran.
  final bool listingFailed;

  /// Size of the written list read before the question.
  final int writtenCount;

  /// "Kept N files": asked, N > 0 and not deleted.
  int get kept => asked && deleted == null ? found : 0;
}
