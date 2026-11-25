/// §AUTOREAD.RULE_MODEL - AUTOREAD RULES model: one remembered person's rule (S0 stub, no behaviour).
library;

/// [autoRecord] may be stored (kinds per [canHoldAutoRecord]) but is dormant:
/// the labeler and Kotlin still treat it as Ask first until autoRecordLive.
enum RuleLevel {
  suggested(0),
  askFirst(1),
  autoRecord(2);

  final int code;
  const RuleLevel(this.code);
}

/// Receiver kinds that can have a rule. Withdrawal and Airtime never do.
enum ReceiverType {
  sendMoney('SM'),
  payBill('PB'),
  buyGoods('BG'),
  pochi('PO');

  final String code;
  const ReceiverType(this.code);
}

/// The one source for which kinds may hold Auto-record: Send Money, Pochi and
/// Till (buyGoods). Paybill is Ask first at most. Withdrawal and Airtime have
/// no rule at all.
bool canHoldAutoRecord(ReceiverType type) => type != ReceiverType.payBill;

/// A valid ceiling is whole cents, 1 up to Ksh 1,000,000 (null means none).
const int kCeilingMinCents = 1;
const int kCeilingMaxCents = 100000000;
bool isValidCeilingCents(int? c) => c == null || (c >= kCeilingMinCents && c <= kCeilingMaxCents);

class ReceiverRule {
  final ReceiverType type;

  /// Normalised key from `receiverKey`.
  final String key;

  /// Display label.
  final String name;
  final RuleLevel level;

  /// Category the rule uses (null while Suggested).
  final int? categoryId;

  /// Records in a row with the same category.
  final int run;
  final int? runCategoryId;
  final DateTime created;
  final DateTime changed;
  final DateTime? lastRecorded;

  /// Auto-record records only up to this amount in cents; above it Ask first.
  /// Null = no ceiling. Compared against the amount alone, fee excluded (A1).
  final int? ceilingCents;

  /// Marker: restored from a file at Auto-record, now Ask first until the
  /// person confirms (A6). Cleared when any level is set for the person.
  final bool autoPending;

  const ReceiverRule({
    required this.type,
    required this.key,
    required this.name,
    this.level = RuleLevel.suggested,
    this.categoryId,
    this.run = 0,
    this.runCategoryId,
    required this.created,
    required this.changed,
    this.lastRecorded,
    this.ceilingCents,
    this.autoPending = false,
  });

  ReceiverRule copyWith({
    String? name,
    RuleLevel? level,
    int? categoryId,
    int? run,
    int? runCategoryId,
    DateTime? changed,
    DateTime? lastRecorded,
    int? ceilingCents,
    bool clearCeiling = false,
    bool? autoPending,
  }) =>
      ReceiverRule(
        type: type,
        key: key,
        name: name ?? this.name,
        level: level ?? this.level,
        categoryId: categoryId ?? this.categoryId,
        run: run ?? this.run,
        runCategoryId: runCategoryId ?? this.runCategoryId,
        created: created,
        changed: changed ?? this.changed,
        lastRecorded: lastRecorded ?? this.lastRecorded,
        ceilingCents: clearCeiling ? null : (ceilingCents ?? this.ceilingCents),
        autoPending: autoPending ?? this.autoPending,
      );

  @override
  bool operator ==(Object other) =>
      other is ReceiverRule &&
      other.type == type &&
      other.key == key &&
      other.name == name &&
      other.level == level &&
      other.categoryId == categoryId &&
      other.run == run &&
      other.runCategoryId == runCategoryId &&
      other.created == created &&
      other.changed == changed &&
      other.lastRecorded == lastRecorded &&
      other.ceilingCents == ceilingCents &&
      other.autoPending == autoPending;

  @override
  int get hashCode => Object.hash(type, key, name, level, categoryId, run, runCategoryId, created, changed, lastRecorded, ceilingCents, autoPending);
}
