/// §AUTOREAD.RULE_CODEC - AUTOREAD RULES codec: one rule as JSON `{v,t,k,name,lv,cat,run,runCat,
/// created,changed,lastRecorded,ceil?,ap?}`. A corrupt value decodes to null (ignored).
library;

import 'dart:convert';

import 'rule_model.dart';

/// Preference key prefix of one rule: prefix + type code + '.' + base64url key.
const String kRuleKeyPrefix = 'autoread_rule_v1.';

/// Key of one rule (base64url of the UTF-8 key, no padding).
String ruleStorageKey(ReceiverType type, String key) =>
    '$kRuleKeyPrefix${type.code}.${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}';

String encodeRule(ReceiverRule r) => jsonEncode(<String, Object?>{
      'v': 1,
      't': r.type.code,
      'k': r.key,
      'name': r.name,
      'lv': r.level.code,
      'cat': r.categoryId,
      'run': r.run,
      'runCat': r.runCategoryId,
      'created': r.created.millisecondsSinceEpoch,
      'changed': r.changed.millisecondsSinceEpoch,
      'lastRecorded': r.lastRecorded?.millisecondsSinceEpoch,
      'ceil': r.ceilingCents,
      'ap': r.autoPending,
    });

/// Null for anything that is not a well-formed version 1 rule.
ReceiverRule? decodeRule(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['v'] != 1) return null;
    ReceiverType? type;
    for (final t in ReceiverType.values) {
      if (t.code == m['t']) type = t;
    }
    RuleLevel? level;
    for (final l in RuleLevel.values) {
      if (l.code == m['lv']) level = l;
    }
    final k = m['k'], name = m['name'], run = m['run'], created = m['created'], changed = m['changed'];
    if (type == null || level == null) return null;
    if (k is! String || k.isEmpty || k.length > 200 || name is! String) return null;
    if (run is! int || run < 0 || created is! int || changed is! int) return null;
    final cat = m['cat'], runCat = m['runCat'], last = m['lastRecorded'];
    if ((cat != null && cat is! int) || (runCat != null && runCat is! int) || (last != null && last is! int)) {
      return null;
    }
    // Optional keys (absent in 0.2.1 rules). A present but bad value = corrupt.
    final ceil = m['ceil'], ap = m['ap'];
    if (ceil != null && (ceil is! int || !isValidCeilingCents(ceil))) return null;
    if (ap != null && ap is! bool) return null;
    return ReceiverRule(
      type: type,
      key: k,
      name: name,
      level: level,
      categoryId: cat as int?,
      run: run,
      runCategoryId: runCat as int?,
      created: DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
      changed: DateTime.fromMillisecondsSinceEpoch(changed, isUtc: true),
      lastRecorded: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last as int, isUtc: true),
      ceilingCents: ceil as int?,
      autoPending: ap == true,
    );
  } catch (_) {
    return null;
  }
}
