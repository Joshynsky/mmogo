/// AUTOREAD RULES model: one remembered person's rule (S0 stub, no behaviour).
library;

/// 0.2.1 only sets [suggested] and [askFirst]. [autoRecord] exists so stored
/// values stay stable; nothing may set or act on it before 0.2.2.
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
  });

  ReceiverRule copyWith({
    String? name,
    RuleLevel? level,
    int? categoryId,
    int? run,
    int? runCategoryId,
    DateTime? changed,
    DateTime? lastRecorded,
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
      other.lastRecorded == lastRecorded;

  @override
  int get hashCode => Object.hash(type, key, name, level, categoryId, run, runCategoryId, created, changed, lastRecorded);
}
