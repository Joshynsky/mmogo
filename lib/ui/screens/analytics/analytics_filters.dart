import '../../../data/db/analytics_dao.dart';
import '../../../domain/format/source_types.dart';

/// §ANALYTICS.FILTERS — the Analytics filter state (0.1.2 S6c, MS1 and TL1):
/// a SET of type codes and a SET of classification names. A row matches when
/// its type is in the type set (OR within types) AND its class is in the class
/// set (OR within classes); an empty set matches everything. Immutable; the
/// screen holds one and replaces it. Pure functions only (no widgets), so it
/// is testable on its own.
class AnalyticsFilters {
  const AnalyticsFilters({this.types = const {}, this.classes = const {}});

  /// No filter: what every period change returns to.
  static const none = AnalyticsFilters();

  /// A hand-off from Home or Paid to (a type and/or a classification name):
  /// a set of one each.
  factory AnalyticsFilters.handOff({String? type, String? classification}) =>
      AnalyticsFilters(types: {?type}, classes: {?classification});

  static const withdrawalCode = 'AGENT_WITHDRAWAL';

  /// Type codes, in the order they were picked (the chip names the first).
  final Set<String> types;

  /// Classification names, in the order they were picked.
  final Set<String> classes;

  bool get isEmpty => types.isEmpty && classes.isEmpty;

  AnalyticsFilters withTypes(Set<String> t) => AnalyticsFilters(types: Set.unmodifiable(t), classes: classes);
  AnalyticsFilters withClasses(Set<String> c) => AnalyticsFilters(types: types, classes: Set.unmodifiable(c));

  AnalyticsFilters toggleType(String code) => withTypes(_toggled(types, code));
  AnalyticsFilters toggleClass(String name) => withClasses(_toggled(classes, name));

  AnalyticsFilters clearTypes() => withTypes(const {});
  AnalyticsFilters clearClasses() => withClasses(const {});

  static Set<String> _toggled(Set<String> s, String v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  /// The 'Ksh X out' subtotal and withdrawn day headers apply when the type
  /// set is exactly {Withdrawal} (S4b-fix2, now set-based).
  bool get onlyWithdrawal => types.length == 1 && types.contains(withdrawalCode);

  bool matches(AnalyticsTransactionRow r) => matchesType(r) && matchesClass(r);

  bool matchesType(AnalyticsTransactionRow r) => types.isEmpty || types.contains(r.sourceType);

  bool matchesClass(AnalyticsTransactionRow r) => classes.isEmpty || classes.contains(r.classificationName);

  List<String> get typeNames => [for (final t in types) sourceTypeName(t)];

  /// One chip for the whole set: the first name, then "+ n more".
  static String chipLabel(List<String> names) =>
      names.isEmpty ? '' : names.length == 1 ? names.first : '${names.first} + ${names.length - 1} more';

  String get typeChipLabel => chipLabel(typeNames);
  String get classChipLabel => chipLabel(classes.toList());

  /// "a, b or c" (the mock's `orList`).
  static String orList(List<String> a) =>
      a.length < 2 ? a.join() : '${a.sublist(0, a.length - 1).join(', ')} or ${a.last}';

  /// The empty-list sentence: the chosen type names, then the chosen
  /// category names in brackets (or alone when no type is chosen).
  String get emptyText {
    final t = orList(typeNames);
    final c = classes.isEmpty ? '' : (types.isEmpty ? orList(classes.toList()) : '(${orList(classes.toList())})');
    final sel = [t, c].where((x) => x.isNotEmpty).join(' ');
    return 'No ${sel.isEmpty ? '' : '$sel '}transactions in this period.';
  }
}

/// The base of the By type percentages: with no type picked, the period's
/// whole spending; with a set picked, the picked types' own total (a
/// Withdrawal in the set adds nothing, it is not spending). [byType] is the
/// per-type amount by code (already following the class set).
int typeShareBase(AnalyticsFilters f, Map<String, int> byType, int totalSpent) {
  if (f.types.isEmpty) return totalSpent;
  var s = 0;
  for (final t in f.types) {
    if (t != AnalyticsFilters.withdrawalCode) s += byType[t] ?? 0;
  }
  return s;
}

/// The percent text on one By type tile: 'tracked' for Withdrawal, a dash
/// for a tile left out of a picked set (or with no base), else its share.
String typeShareText(AnalyticsFilters f, String code, int cents, int base) {
  if (code == AnalyticsFilters.withdrawalCode) return 'tracked';
  if (f.types.isNotEmpty && !f.types.contains(code)) return '—';
  return base > 0 ? '${(cents / base * 100).round()}%' : '—';
}
