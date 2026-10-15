import '../../domain/format/source_types.dart';
import 'backup_limits.dart';
import 'backup_repair.dart';

/// §DATA.BACKUP.DESCRIBER — 0.1.2 S10a (A2b, A3, CB8). Describes a row that
/// could not go into a backup / safety copy WITHOUT its content: what kind of
/// row it is, for an entry its date and type, and a reason CODE. Never an
/// amount, a name, a phone number, a code or any other value, so the result is
/// safe to show, log and put in a test failure message.
///
/// Phone-side wording is the UI's (CB8: "lost" / "not kept in the safety
/// copy"); "skipped" stays in the file-side result table.

/// What a described row is.
enum SkipKind { entry, category, savedReceiver }

/// Why a row was left out. Three of these are the signed mock reasons, the
/// fourth is a row that went with its category (wording decided in S10b).
enum SkipReason {
  /// "A required detail is missing."
  missingDetail,

  /// "A value is not allowed."
  notAllowed,

  /// "The entry could not be read."
  couldNotRead,

  /// The row's category was left out, so it went with it.
  cascaded,
}

/// Every rule name the repair (and the validator, by `RestoreRejectReason.name`)
/// can produce, mapped to a reason. [skipReasonFor] adds the default, so a rule
/// added later still maps (to [SkipReason.couldNotRead]); a test fails when a
/// rule in the source is missing from this table.
const Map<String, SkipReason> kSkipRuleReasons = {
  // backup_repair.dart
  'empty': SkipReason.missingDetail,
  'missing': SkipReason.missingDetail,
  'length': SkipReason.notAllowed,
  'characters': SkipReason.notAllowed,
  'format': SkipReason.notAllowed,
  'range': SkipReason.notAllowed,
  'duplicate': SkipReason.notAllowed,
  'unknown value': SkipReason.notAllowed,
  'not allowed for source': SkipReason.notAllowed,
  'paired with label': SkipReason.notAllowed,
  'group is switched off': SkipReason.notAllowed,
  'group does not match': SkipReason.notAllowed,
  'type': SkipReason.couldNotRead,
  'dangling reference': SkipReason.couldNotRead,
  'its classification was skipped': SkipReason.cascaded,
  // RestoreRejectReason names (the validator's own backstop).
  'invalidRow': SkipReason.notAllowed,
  'danglingRef': SkipReason.couldNotRead,
  'notMmogo': SkipReason.couldNotRead,
  'newer': SkipReason.couldNotRead,
  'corrupt': SkipReason.couldNotRead,
  'tooLarge': SkipReason.couldNotRead,
  'tooMany': SkipReason.couldNotRead,
};

/// The ONE total function from a rule name to a reason.
SkipReason skipReasonFor(String rule) => kSkipRuleReasons[rule] ?? SkipReason.couldNotRead;

/// What the describer may know about an entry: its date and type fields read
/// from the SAME read as the export. Raw, unchecked values.
class EntryFacts {
  const EntryFacts({this.occurredAtMs, this.sourceType});
  final Object? occurredAtMs;
  final Object? sourceType;
}

/// One described row. Date and type only for an entry that could be read.
class SkippedRowInfo {
  const SkippedRowInfo({required this.kind, required this.reason, this.date, this.type});

  final SkipKind kind;
  final SkipReason reason;

  /// Entries only: when the entry happened (local time). Null when unreadable.
  final DateTime? date;

  /// Entries only: the source type code. Null when unreadable.
  final String? type;

  /// Entries only: the type's display name (`Send Money`), else null.
  String? get typeName => type == null ? null : sourceTypeName(type!);

  /// An entry whose date or type could not be read: shown as "an entry that
  /// could not be read".
  bool get unreadable => kind == SkipKind.entry && (date == null || type == null);

  /// Never holds a value; safe in a log.
  @override
  String toString() => 'SkippedRowInfo(${kind.name}, ${reason.name}'
      '${date == null ? '' : ', ${date!.year}-${date!.month}-${date!.day}'}'
      '${type == null ? '' : ', $type'})';
}

/// A capped view of described rows: the exact count always, the first
/// [cap] rows, and how many are not shown.
class SkippedSummary {
  const SkippedSummary({required this.count, required this.shown});

  static const int cap = 20;
  static const SkippedSummary empty = SkippedSummary(count: 0, shown: []);

  factory SkippedSummary.of(List<SkippedRowInfo> all) => SkippedSummary(
        count: all.length,
        shown: List.unmodifiable(all.length <= cap ? all : all.sublist(0, cap)),
      );

  /// N, exactly.
  final int count;
  final List<SkippedRowInfo> shown;

  /// "and M more not shown".
  int get moreNotShown => count - shown.length;
}

/// Pure. Describes [skipped] (the repair's report: table, row id, field,
/// rule). [entryFacts] maps a transaction id to its date and type fields as
/// read; a missing id, a bad type or an out-of-range date makes the entry
/// unreadable. Order is kept.
List<SkippedRowInfo> describeSkipped(
  List<BackupSkippedRow> skipped, {
  required Map<int, EntryFacts> entryFacts,
}) {
  return [
    for (final s in skipped)
      switch (s.table) {
        'transactions' => _entry(s, entryFacts[s.rowId]),
        'classifications' => SkippedRowInfo(kind: SkipKind.category, reason: skipReasonFor(s.rule)),
        _ => SkippedRowInfo(kind: SkipKind.savedReceiver, reason: skipReasonFor(s.rule)),
      },
  ];
}

SkippedRowInfo _entry(BackupSkippedRow s, EntryFacts? f) {
  final reason = skipReasonFor(s.rule);
  final at = f?.occurredAtMs;
  final type = f?.sourceType;
  if (at is int &&
      at >= kBackupMinEpochMs &&
      at < kBackupMaxEpochMs &&
      type is String &&
      kBackupSourceTypes.contains(type)) {
    return SkippedRowInfo(
      kind: SkipKind.entry,
      reason: reason,
      date: DateTime.fromMillisecondsSinceEpoch(at),
      type: type,
    );
  }
  return SkippedRowInfo(kind: SkipKind.entry, reason: reason);
}

/// Rows per table: in the file/safety copy, left out, and live on the phone.
/// "included + skipped = live" is [holds].
class TableIdentity {
  const TableIdentity({required this.included, required this.skipped, required this.live});
  final int included;
  final int skipped;
  final int live;
  bool get holds => included + skipped == live;

  @override
  String toString() => 'TableIdentity(included: $included, skipped: $skipped, live: $live)';
}

/// [TableIdentity] for the three backed-up tables. Transactions are live
/// (not recently deleted) rows; classifications are all of them.
class ReplaceIdentity {
  const ReplaceIdentity({
    required this.transactions,
    required this.classifications,
    required this.counterpartyMap,
  });
  final TableIdentity transactions;
  final TableIdentity classifications;
  final TableIdentity counterpartyMap;

  bool get holds => transactions.holds && classifications.holds && counterpartyMap.holds;
  int get skippedTotal => transactions.skipped + classifications.skipped + counterpartyMap.skipped;
}
