/// AUTOREAD QUEUED_YES (0.2.1 Ask first): a Yes tapped on a phone alert is QUEUED by Kotlin (one preference
/// key per waiting item, holding the tap time) and the app records it the next time it ingests (open or
/// resume). Nothing is recorded without that tap, and nothing is trusted from Kotlin beyond "this id was
/// tapped": what to record comes from the item's own stored hint.
///
/// This file holds the whole import in small pieces so each can be read alone:
///  - [YesMarks] / [PrefsYesMarks]: the marks (read, remove).
///  - [pickQueuedYes]: PURE. Which items to record, and which marks to drop.
///  - [QueuedYesImporter]: runs the picks through the repository's own save, with the duplicate-code
///    protection (codes the user just undid are never recorded again).
///  - [CategoryNameCache]: the names the Kotlin alert shows ("Record as [Category]?").
/// Lives under `lib/autoread/` so the standard build drops it. No message text is read or stored here.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/rule_hint.dart';
import '../model/waiting_item.dart';
import '../rules/rule_codec.dart' show decodeRule, kRuleKeyPrefix;
import '../rules/rule_model.dart';
import '../rules/undone_codes.dart';

/// One mark per waiting item: prefix plus the 32-hex id; value = tap time in ms (an int). Written ONLY by Kotlin
/// (AskStore.YES_PREFIX has "flutter." in front). Not in the backup key table.
const String kYesMarkPrefix = 'autoread_yes_v1.';

/// The whole queued-Yes step of one ingest (marks, saves, category names) may take at most this long; past it
/// the ingest goes on without it and tries again next time. Normal use takes milliseconds.
const Duration kQueuedYesBudget = Duration(seconds: 1);

/// A mark older than this is dropped unrecorded (the item itself lives 24 h).
const Duration kYesMarkLife = Duration(hours: 24);

/// Category names for the Kotlin alert: JSON object, id to name. Written by the app, read by Kotlin
/// (AskStore.NAMES_KEY). Device only, never in a backup, removed by Delete data with the other rule data.
const String kCategoryNamesKey = 'autoread_cat_names_v1';

abstract class YesMarks {
  /// Item id -> tap time. Reloads first (Kotlin wrote it from another thread).
  Future<Map<String, DateTime>> read();

  Future<void> remove(Iterable<String> ids);
}

class PrefsYesMarks implements YesMarks {
  PrefsYesMarks({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _prefs;

  @override
  Future<Map<String, DateTime>> read() async {
    final p = await _prefs();
    await p.reload();
    final out = <String, DateTime>{};
    for (final k in p.getKeys().where((k) => k.startsWith(kYesMarkPrefix))) {
      final id = k.substring(kYesMarkPrefix.length);
      final at = p.get(k);
      if (isValidHeldId(id) && at is int) out[id] = DateTime.fromMillisecondsSinceEpoch(at);
    }
    return out;
  }

  @override
  Future<void> remove(Iterable<String> ids) async {
    final p = await _prefs();
    for (final id in ids) {
      await p.remove('$kYesMarkPrefix$id');
    }
  }
}

/// One item to record and the category its own Ask first hint offers.
class QueuedYesPick {
  const QueuedYesPick(this.item, this.categoryId);
  final WaitingItem item;
  final int categoryId;
}

/// What [pickQueuedYes] decided: the [picks] to record, and the mark ids to [drop] without recording
/// (expired, no such item any more, no Ask first hint now, or the code was undone).
class QueuedYesPlan {
  const QueuedYesPlan(this.picks, this.drop);
  final List<QueuedYesPick> picks;
  final List<String> drop;
}

/// PURE. A mark leads to a record only when ALL hold: it is younger than [kYesMarkLife] (and not from the
/// future), the item is parsed and waiting, its hint is Ask first with a category to offer, and its M-Pesa
/// code is not in [undoneCodes]. Any other mark is dropped. Marks of items not seen here are dropped too
/// (the item was recorded or removed meanwhile).
QueuedYesPlan pickQueuedYes({
  required Iterable<WaitingItem> items,
  required Map<String, DateTime> marks,
  required Set<String> undoneCodes,
  required DateTime now,
}) {
  final byId = {for (final i in items) i.id: i};
  final picks = <QueuedYesPick>[];
  final drop = <String>[];
  for (final e in marks.entries) {
    final age = now.difference(e.value);
    final item = byId[e.key];
    final hint = item?.hint;
    final fresh = !age.isNegative && age < kYesMarkLife;
    final asks = item != null &&
        item.kind == WaitingKind.waitingCategory &&
        hint != null &&
        hint.level == RuleLevel.askFirst &&
        hint.suggested.isNotEmpty;
    if (!fresh || !asks || undoneCodes.contains(item.parsed!.code)) {
      drop.add(e.key);
    } else {
      picks.add(QueuedYesPick(item, _first(hint)));
    }
  }
  return QueuedYesPlan(picks, drop);
}

int _first(RuleHint h) => h.suggested.first;

/// What the importer did for one item (for the "Recorded as ..." notice with Undo).
class QueuedYesRecorded {
  const QueuedYesRecorded({required this.itemId, required this.rowId, required this.amountCents, required this.categoryId});
  final String itemId;

  /// The ledger row written (Undo moves it to Recently deleted).
  final int rowId;
  final int amountCents;
  final int categoryId;
}

class QueuedYesImporter {
  QueuedYesImporter({
    required this.marks,
    required this.undone,
    required this.categoryActive,
    required this.record,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final YesMarks marks;
  final UndoneCodes undone;

  /// True when the category still exists and is active (a deleted category is never recorded into).
  final Future<bool> Function(int categoryId) categoryActive;

  /// The repository's own save (the one the Categorize sheet and the airtime auto path use): the new ledger
  /// row id, or null when nothing was written (the code was already recorded).
  final Future<int?> Function(String itemId, int categoryId) record;
  final DateTime Function() _now;

  /// Records every queued Yes that is still valid. Never throws. A save that fails keeps its mark (tried
  /// again at the next ingest, until the mark expires); everything else is removed.
  Future<List<QueuedYesRecorded>> run(List<WaitingItem> items) async {
    final done = <QueuedYesRecorded>[];
    try {
      final all = await marks.read();
      if (all.isEmpty) return done;
      final now = _now();
      final undoneCodes = <String>{
        for (final i in items)
          if (i.parsed != null && await undone.contains(i.parsed!.code, now: now)) i.parsed!.code,
      };
      final plan = pickQueuedYes(items: items, marks: all, undoneCodes: undoneCodes, now: now);
      final finished = <String>[...plan.drop];
      for (final p in plan.picks) {
        try {
          if (!await categoryActive(p.categoryId)) {
            finished.add(p.item.id); // the category is gone: the item stays in To do for a human choice
            continue;
          }
          final row = await record(p.item.id, p.categoryId);
          finished.add(p.item.id);
          if (row != null) {
            done.add(QueuedYesRecorded(
                itemId: p.item.id, rowId: row, amountCents: p.item.parsed!.amountCents, categoryId: p.categoryId));
          }
        } catch (_) {
          // Keep the mark; the item is still there.
        }
      }
      await marks.remove(finished);
    } catch (_) {}
    return done;
  }
}

/// Writes the active category names for the Kotlin alert. Names are labels the user typed; they are kept only
/// on this device and shown on an alert only with "Show details" on and an unlocked phone.
class CategoryNameCache {
  CategoryNameCache({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _prefs;

  /// Replaces the stored names with [names] (id -> name). Never throws.
  Future<void> write(Map<int, String> names) async {
    try {
      final p = await _prefs();
      if (names.isEmpty) {
        await p.remove(kCategoryNamesKey);
      } else {
        await p.setString(kCategoryNamesKey, jsonEncode({for (final e in names.entries) '${e.key}': e.value}));
      }
    } catch (_) {}
  }
}

/// True when some stored rule is above Suggested (Ask first, or a stored Auto-record shown as Ask first). Only
/// then does the alert need category names, so the database is not opened for them otherwise. Never throws.
Future<bool> anyAskFirstRuleStored({Future<SharedPreferences> Function()? prefs}) async {
  try {
    final p = await (prefs ?? SharedPreferences.getInstance)();
    await p.reload();
    return p.getKeys().where((k) => k.startsWith(kRuleKeyPrefix)).any((k) {
      final r = decodeRule(p.get(k));
      return r != null && r.level != RuleLevel.suggested;
    });
  } catch (_) {
    return false;
  }
}
