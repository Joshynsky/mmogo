/// §AUTOREAD.REAL_WAITING_REPO — the real [AutoReadWaitingRepository]: what the
/// Notifications page and the bell show in the autoread flavor.
///
/// Where the rows come from:
/// - PARSED items live in the per-item store ([PendingItemsStore]).
/// - HELD messages (Kotlin side) are listed with `listHeldIds` and each one is
///   looked at once through [AutoReadService.inspect]: readable becomes a
///   ready-to-parse row, anything else becomes an UNREADABLE row (nothing is
///   hidden: this is the "Other messages" list). The body is parsed and dropped;
///   only the kind and the held time are kept in memory.
/// - Read off does not clear anything (PM 19-10-2026): this repository keeps
///   ingesting and showing what is held while Read is off; the held window
///   ([kHeldWindow]) still applies.
///
/// Ingest runs on [ingest]: the app calls it on start, on resume and after a
/// notification tap; it also runs itself when Kotlin pushes an Auto-record
/// arrival while the app is in front (0.2.2 B-4, see [_onArrived]). A timer on the next expiry re-emits so the bell numbers
/// drop without a user action. All state changes run one after another.
///
/// Save order (see [saveCategory]): transaction first, then the waiting item
/// leaves, then the held copy is acked. A crash between any two steps leaves
/// either the item (retry is a no-op for the transaction) or nothing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/app_database.dart';
import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../data/db/classification_dao.dart';
import '../../data/db/linked_cash_dao.dart';
import '../../data/db/counterparty_dao.dart';
import '../../data/db/transaction_dao.dart';
import '../../data/prefs/app_prefs.dart';
import '../../domain/airtime/airtime_kind.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/widgets/withdrawal_use_block.dart' show WdCreateResult;
import '../../ui/widgets/withdrawal_use_create.dart' as wd_create;
import '../../ui/screens/add/add_draft.dart';
import '../bridge/autoread_bridge.dart';
import '../held_window.dart';
import '../logic/airtime_auto.dart';
import '../logic/message_details.dart';
import '../model/held_description.dart';
import '../model/waiting_item.dart';
import '../rules/prefs_undone_codes.dart' show PrefsUndoneCodes;
import '../rules/undone_codes.dart' show UndoneCodes;
import 'hard_rule_arrival.dart';
import 'hard_rule_arrival_toast.dart';
import 'queued_yes.dart';
import 'queued_yes_toast.dart';
import '../model/waiting_repository.dart';
import '../service/autoread_service.dart';
import '../ui/category_choices.dart';
import 'airtime_trail_join.dart';
import 'airtime_trail_store.dart';
import 'fuliza_event_saver.dart';
import 'held_describer.dart';
import 'pending_items_store.dart';
import 'real_category_choices.dart';

part 'real_waiting_withdrawal.dart';
part 'real_waiting_auto.dart';

typedef TimerFactory = Timer Function(Duration after, void Function() callback);

/// Saved-transaction lookup for the service: is this M-Pesa code already a
/// (non-deleted, non-cash) transaction? The same check Add makes.
class TransactionCodeLookup implements CodeLookup {
  TransactionCodeLookup(this._db);
  final Future<Database> Function() _db;

  @override
  Future<bool> contains(String displayCode) async =>
      TransactionDao.mpesaCodeExists(await _db(), code: displayCode);
}

class _Held {
  const _Held(this.kind, this.heldAt);
  final WaitingKind kind; // readyToParse, unreadable or gone
  final DateTime heldAt;
}

class RealWaitingRepository implements AutoReadWaitingRepository {
  RealWaitingRepository({
    required AutoReadBridge bridge,
    required PendingItemsStore store,
    required AutoReadService service,
    Future<Database> Function()? database,
    DateTime Function()? now,
    Future<bool> Function()? captureIdentity,
    void Function()? onSaved,
    TimerFactory? timer,
    Future<bool> Function()? readAirtimeAuto,
    Future<void> Function(bool on)? writeAirtimeAuto,
    Future<bool> Function()? readAirtimeAutoOther,
    Future<void> Function(bool on)? writeAirtimeAutoOther,
    FulizaEventSaver? fulizaSaver,
    AirtimeTrailStore? trailStore,
    YesMarks? yesMarks,
    UndoneCodes? undoneCodes,
    void Function(List<QueuedYesRecorded> recorded)? onQueuedYes,
    bool queuedYes = true,
    AutoMarks? autoMarks,
    Future<bool> Function(WaitingItem item)? autoRecheck,
    bool? autoRecordLive,
    bool Function()? inFront,
  })  : _inFront = inFront ?? _appInFront,
        _queuedYesOn = queuedYes,
        _autoMarks = autoMarks,
        _autoRecheck = autoRecheck,
        _autoLive = autoRecordLive,
        _yesMarks = yesMarks,
        _undoneCodes = undoneCodes,
        _onQueuedYes = onQueuedYes,
        _fulizaSaver = fulizaSaver,
        _trailStore = trailStore ?? AirtimeTrailStore(prefs: MemoryTrailPrefs(), now: now ?? DateTime.now),
        _bridge = bridge,
        _store = store,
        _service = service,
        _database = database ?? (() => AppDatabase.instance.database),
        _now = now ?? DateTime.now,
        _captureIdentity = captureIdentity ?? AppPrefs.readCaptureIdentityPreference,
        _onSaved = onSaved ?? (() {}),
        _timerFactory = timer ?? Timer.new,
        _readAirtimeAuto = readAirtimeAuto ?? _prefsReadAirtimeAuto,
        _writeAirtimeAuto = writeAirtimeAuto ?? _prefsWriteAirtimeAuto,
        _readAirtimeAutoOther = readAirtimeAutoOther ?? _prefsReadAirtimeAutoOther,
        _writeAirtimeAutoOther = writeAirtimeAutoOther ?? _prefsWriteAirtimeAutoOther {
    _arrivedSub = bridge.arrived.listen((_) => _onArrived(), onError: (Object _) {});
  }

  // 0.2.2 item 2 (B-4): Kotlin pushes `onArrived` after it queued an Auto-record arrival. While the app is in
  // front the import runs at once (the same [ingest] as open and resume; its queue means a resume or a second
  // arrival at the same moment finds the mark already finished, so nothing is recorded twice). In the background
  // nothing runs here: the resume ingest records it when the user comes back, with the toast in view.
  final bool Function() _inFront;
  StreamSubscription<void>? _arrivedSub;

  static bool _appInFront() {
    try {
      return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } catch (_) {
      return false; // no binding (a plain test): never import on our own
    }
  }

  void _onArrived() {
    // Not before the app's own first ingest (it runs after the consent check on start).
    if (_closed || !_ingestStarted || !_inFront()) return;
    unawaited(ingest().catchError((Object _) {}));
  }

  final AutoReadBridge _bridge;
  final PendingItemsStore _store;
  final AutoReadService _service;
  final Future<Database> Function() _database;
  final DateTime Function() _now;
  final Future<bool> Function() _captureIdentity;
  /// Called once after a real transaction was written (not for an already
  /// recorded code). Left empty by default: see the hand-back about auto-backup.
  final void Function() _onSaved;
  final TimerFactory _timerFactory;
  final Future<bool> Function() _readAirtimeAuto;
  final Future<void> Function(bool on) _writeAirtimeAuto;
  final Future<bool> Function() _readAirtimeAutoOther;
  final Future<void> Function(bool on) _writeAirtimeAutoOther;

  /// Saves Fuliza events from held messages (S12 slice D); null = not saving.
  final FulizaEventSaver? _fulizaSaver;

  // A Yes tapped on a phone alert is recorded here at ingest (see queued_yes.dart). Marks and undone codes
  // default to the real preference stores; the callback default shows the toast with Undo.
  /// False: the step is skipped (a widget test under fake time cannot reach the phone's preferences).
  final bool _queuedYesOn;
  final YesMarks? _yesMarks;
  final UndoneCodes? _undoneCodes;
  final void Function(List<QueuedYesRecorded> recorded)? _onQueuedYes;

  // 0.2.2 item 2 (B2d): an Auto-record arrival is the same import with an AUTOMATIC mark, re-checked from fresh
  // preferences (hard_rule_arrival.dart) and written through the same save, then marked recorded_automatically.
  // Null = the real stores; [_autoLive] null = autoRecordLive (false: automatic marks are dropped unrecorded).
  final AutoMarks? _autoMarks;
  final Future<bool> Function(WaitingItem item)? _autoRecheck;
  final bool? _autoLive;
  late final QueuedYesImporter _queuedYes = QueuedYesImporter(
    marks: _yesMarks ?? PrefsYesMarks(),
    undone: _undoneCodes ?? PrefsUndoneCodes(),
    categoryActive: _categoryActive,
    record: _saveInner,
    now: _now,
    autoMarks: _autoMarks ?? PrefsAutoMarks(),
    autoRecheck: _autoRecheck ?? HardRuleRecheck().passes,
    markAutomatic: _markAutomatic,
    cancelAlert: _bridge.cancelAlert, // B-2: the "Queued" alert leaves the shade once its mark is finished
    live: _autoLive,
  );
  Map<int, String> _namesWritten = const {};

  /// The stored 24 h trail (row numbers and times). Written only by [_autoRecordPending].
  final AirtimeTrailStore _trailStore;

  /// The Airtime auto-record switch and trail (J2). OFF until the user opts in.
  late final AirtimeAutoController airtime =
      AirtimeAutoController(
          onSwitch: setAirtimeAuto, onUndo: undoAutoRecord, onSwitchOther: setAirtimeAutoOther, now: _now);

  final Map<String, _Held> _held = {};

  /// In-memory descriptions of held messages (never stored); see [HeldDescriber].
  late final HeldDescriber _describer = HeldDescriber(
    service: _service,
    runLocked: _locked,
    kindOf: (id) {
      final h = _held[id];
      return h == null || heldExpired(h.heldAt, _now()) ? null : h.kind;
    },
  );
  List<WaitingItem> _current = const [];

  /// Ids of airtime items the app tried to add by itself and could not.
  final Set<String> _stuck = {};
  final StreamController<List<WaitingItem>> _changes = StreamController<List<WaitingItem>>.broadcast();
  final Completer<void> _ready = Completer<void>();
  Future<void> _tail = Future<void>.value();
  Timer? _timer;
  bool _closed = false;
  bool _ingestStarted = false;

  // ------------------------------------------------------------ plumbing

  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Rebuilds the list from the store and the held cache, emits it and sets the
  /// next expiry timer. Call inside [_locked].
  Future<void> _publish() async {
    List<WaitingItem> stored;
    try {
      stored = await _store.list();
    } catch (_) {
      stored = [
        for (final i in _current)
          if (i.kind == WaitingKind.waitingCategory) i,
      ];
    }
    _current = List.unmodifiable([
      ...visibleWaiting(stored, myselfOn: airtime.on, otherOn: airtime.onOther, stuckIds: _stuck),
      for (final e in _held.entries) WaitingItem(id: e.key, kind: e.value.kind, heldAt: e.value.heldAt),
    ]);
    _describer.sync({for (final e in _held.entries) e.key: e.value.kind});
    if (!_closed) _changes.add(_current);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _timer?.cancel();
    _timer = null;
    if (_closed) return;
    final t = _now();
    DateTime? next;
    for (final h in _held.values) {
      if (h.kind == WaitingKind.gone || heldExpired(h.heldAt, t)) continue;
      final at = h.heldAt.add(kHeldWindow);
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next == null) return;
    _timer = _timerFactory(next.difference(t) + const Duration(seconds: 1), () {
      if (_closed) return;
      unawaited(_locked(_publish));
    });
  }

  void dispose() {
    final firstClose = !_closed;
    _closed = true;
    // A second dispose() must stay harmless (tests and shutdown can both call it).
    if (firstClose) undecided.dispose();
    unawaited(_arrivedSub?.cancel());
    _arrivedSub = null;
    _describer.clear();
    _timer?.cancel();
    unawaited(_changes.close());
  }

  // ------------------------------------------------------------- reading

  /// The current list first (after the first ingest), then again after every
  /// change.
  @override
  Stream<List<WaitingItem>> watch() {
    late StreamController<List<WaitingItem>> c;
    StreamSubscription<List<WaitingItem>>? sub;
    c = StreamController<List<WaitingItem>>(
      onListen: () async {
        if (!_ingestStarted) unawaited(ingest());
        await _ready.future;
        if (c.isClosed || _closed) return;
        c.add(_current);
        sub = _changes.stream.listen(c.add, onError: c.addError);
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  /// Lists the held ids, looks at each one not seen yet and emits. Safe to call
  /// at any time (start, resume, after a tap, after Delete data).
  Future<void> ingest() {
    _ingestStarted = true;
    return _locked(() async {
      try {
        airtime.setOn(await _readAirtimeAuto());
      } catch (_) {
        // Unreadable preference: keep what we know (OFF at start).
      }
      try {
        airtime.setOnOther(await _readAirtimeAutoOther());
      } catch (_) {
        // Same: keep what we know.
      }
      List<String>? ids;
      try {
        ids = await _bridge.listHeldIds();
      } catch (_) {
        ids = null; // keep what we know
      }
      if (ids != null) {
        final present = ids.where(isValidHeldId).toSet();
        _held.removeWhere((id, _) => !present.contains(id));
        for (final id in present) {
          if (_held.containsKey(id)) continue;
          await _saveFulizaFrom(id);
          try {
            final r = await _service.inspect(id);
            switch (r.look) {
              case HeldLook.readable:
                _held[id] = _Held(WaitingKind.readyToParse, r.heldAt!);
              case HeldLook.unreadable:
                _held[id] = _Held(WaitingKind.unreadable, r.heldAt!);
              case HeldLook.duplicate:
              case HeldLook.gone:
              case HeldLook.busy:
              case HeldLook.ignored:
                break;
            }
          } catch (_) {
            // One bad message must not stop the others; it is looked at again next time.
          }
        }
      }
      await _reloadTrail();
      await _autoRecordPending();
      await _importQueuedYes();
      await _publish();
      if (!_ready.isCompleted) _ready.complete();
    });
  }

  /// Looks once at held message [id] for a Fuliza draw or repayment and saves
  /// it as an event BEFORE the body is dropped. Never throws, never changes the
  /// row (the item shows in Notifications exactly as before). Returns true when
  /// a new event was stored.
  Future<bool> _saveFulizaFrom(String id) async {
    final saver = _fulizaSaver;
    if (saver == null || !isValidHeldId(id)) return false;
    try {
      final held = await _bridge.peekHeld(id);
      if (held == null) return false;
      return await saver.save(held.body, held.heldAt);
    } catch (_) {
      return false;
    }
  }

  /// Re-looks at every held message and stores the Fuliza events not stored yet
  /// (the "Rebuild from my messages" button). ADDS only, never deletes; only
  /// messages still held can be used. Returns how many events were added.
  /// The merge sets `FulizaRebuild.hook = rebuildFromHeld`.
  Future<int> rebuildFromHeld() => _locked(() async {
        List<String> ids;
        try {
          ids = await _bridge.listHeldIds();
        } catch (_) {
          return 0;
        }
        var added = 0;
        for (final id in ids.where(isValidHeldId).toSet()) {
          if (await _saveFulizaFrom(id)) added++;
        }
        return added;
      });

  /// The row with this id in the latest list, or null.
  WaitingItem? itemById(String id) => _current.where((i) => i.id == id).firstOrNull;

  // ------------------------------------------------------------- details

  /// The content of the Details sheet for row [id], or null when the row is no
  /// longer in the list. A held message is looked at once (see
  /// [AutoReadService.lookForDetails]); nothing is stored or acked.
  Future<MessageDetails?> detailsFor(String id) async {
    final item = itemById(id);
    if (item == null) return null;
    final now = _now();
    if (item.kind == WaitingKind.waitingCategory || item.kind == WaitingKind.gone) {
      return buildMessageDetails(item, now);
    }
    if (item.isExpiredAt(now)) return buildMessageDetails(item, now, expired: true);
    final look = await _locked(() => _service.lookForDetails(id)); // queued with Parse: never holds the claim at the same time
    switch (look.look) {
      case HeldLook.readable:
        return buildMessageDetails(item, now, fields: look.fields);
      case HeldLook.unreadable:
        return buildMessageDetails(item, now, light: look.light);
      case HeldLook.gone:
      case HeldLook.duplicate:
      case HeldLook.ignored:
        return buildMessageDetails(item, now, expired: true);
      case HeldLook.busy:
        // Someone else is parsing it: show what the row already knows.
        return buildMessageDetails(item, now);
    }
  }

  // ------------------------------------------------------------- actions

  @override
  Future<ParseOutcome> parse(String id) => _locked(() async {
        final h = _held[id];
        final outcome = await _service.parse(id);
        switch (outcome) {
          case ParseOutcome.parsed:
          case ParseOutcome.duplicate:
            _held.remove(id);
          case ParseOutcome.couldNotRead:
            if (h != null) _held[id] = _Held(WaitingKind.unreadable, h.heldAt);
          case ParseOutcome.gone:
            if (h != null) _held[id] = _Held(WaitingKind.gone, h.heldAt);
        }
        if (outcome == ParseOutcome.parsed) await _autoRecordPending();
        await _publish();
        return outcome;
      });

  /// Parses each of [ids] one after another; returns how many ended as parsed.
  Future<int> parseAll(Iterable<String> ids) async {
    var n = 0;
    for (final id in ids) {
      if (await parse(id) == ParseOutcome.parsed) n++;
    }
    return n;
  }

  @override
  Future<void> remove(String id) => _locked(() async {
        final item = _current.where((i) => i.id == id).firstOrNull;
        if (item == null) return;
        checkRemovable(item, _now());
        // The held copy goes first; if that fails the row stays (and says so
        // by throwing), so nothing is half removed.
        await _bridge.ackHeld(id, generation: await _bridge.readGeneration());
        _held.remove(id);
        await _publish();
      });

  /// A short description of a held message for its row, or null (the row keeps
  /// its plain title). Runs inside the queue, one look per id per page visit.
  Future<HeldDescription?> describeHeld(String id) => _describer.describe(id);

  /// Forgets every description (page closed, app hidden, Delete data).
  void clearDescriptions() => _describer.clear();

  /// Tests only: how many ids hold an answer.
  @visibleForTesting
  int get describedCount => _describer.cachedCount;

  /// The categories the Categorize sheet offers for [item] (the same ones Add
  /// shows for its type).
  Future<CategoryChoices> categoryChoicesFor(WaitingItem item) async {
    final type = item.parsed?.sourceType;
    if (type == null) throw StateError('Only a parsed item can be categorized.');
    return RealCategoryChoices(await _database(), type, airtimeOther: item.parsed!.airtimeOther);
  }

  /// 0.2.1: the undecided withdrawals, kept live for the Notifications item AND the bell (the bell
  /// counts the decision item as ONE). Reloaded by [refreshUndecided].
  final ValueNotifier<List<AnalyticsTransactionRow>> undecided = ValueNotifier(const []);

  /// Saves the waiting item [id] as a real transaction under [categoryId] (a
  /// classification id in decimal), then removes it.
  ///
  /// Order and crash analysis:
  /// 1. Write the transaction (skipped when this code is already recorded, so
  ///    a retry or a paste of the same payment never makes a second row).
  /// 2. Remove the waiting item.
  /// 3. Ack the held message (best effort).
  /// A crash after 1 leaves the item: retrying finds the code recorded, skips
  /// the write and finishes 2 and 3. A crash after 2 leaves at most the held
  /// copy, which the next ingest recognises as an already saved payment and
  /// drops. Nothing is lost and nothing is written twice.
  @override
  Future<void> saveCategory(String id, String categoryId) => _locked(() async {
        final cls = int.tryParse(categoryId);
        if (cls == null) throw ArgumentError.value(categoryId, 'categoryId', 'not a category id');
        await _saveInner(id, cls);
        await _publish();
      });

  /// 0.2.2 suggested chip: the SAME save as [saveCategory] (same transaction, same order, same ledger hooks),
  /// but it checks inside the one queue step that the category is still active, and it hands back the new
  /// ledger row id so the caller can offer Undo. [ChipRecordResult.active] false: nothing was written and the
  /// item keeps waiting. [ChipRecordResult.rowId] null with active true: nothing new was written (the item was
  /// gone or its code was already recorded). A second call for the same item finds it gone: no second entry.
  Future<ChipRecordResult> recordChip(String id, String categoryId) => _locked(() async {
        final cls = int.tryParse(categoryId);
        if (cls == null) throw ArgumentError.value(categoryId, 'categoryId', 'not a category id');
        if (!await _categoryActive(cls)) return const ChipRecordResult(active: false);
        final rowId = await _saveInner(id, cls);
        if (rowId != null) await _noteTrail(rowId);
        await _publish();
        return ChipRecordResult(active: true, rowId: rowId);
      });

  /// 0.2.2 (F10): the in-app Ask first "Yes": the SAME save as [saveCategory], and the new entry is listed
  /// under Recorded automatically (with Undo). Never throws on the listing itself.
  Future<void> saveCategoryListed(String id, String categoryId) => _locked(() async {
        final cls = int.tryParse(categoryId);
        if (cls == null) throw ArgumentError.value(categoryId, 'categoryId', 'not a category id');
        final rowId = await _saveInner(id, cls);
        if (rowId != null) await _noteTrail(rowId);
        await _publish();
      });

  /// 0.2.2 (F10, contract 6e): lists [rowId] (a chip tap or an Ask first Yes) under Recorded automatically.
  /// It uses the existing 24 h trail (row number and time only; no schema change, no column flag). The
  /// ledger column `recorded_automatically` stays for rows written with no tap at all. Inside [_locked].
  Future<void> _noteTrail(int rowId) async {
    try {
      await _reloadTrail(await _trailStore.add(rowId, _now()));
    } catch (_) {}
  }

  /// Undo of a chip-recorded entry: Recently deleted (restorable for 1 hour). A row already deleted or gone is
  /// left alone (a second Undo must not move its 1 hour window).
  Future<void> undoChipRecord(int rowId) => _locked(() async {
        final db = await _database();
        final row =
            (await db.query('transactions', columns: ['deleted_at'], where: 'id = ?', whereArgs: [rowId])).firstOrNull;
        if (row != null && row['deleted_at'] == null) {
          await TransactionDao.softDelete(db, id: rowId);
          _onSaved();
        }
        await _reloadTrail();
      });

  /// The save itself, inside [_locked]; returns the new ledger row id, or null
  /// when nothing was written (item gone, or the code was already recorded).
  Future<int?> _saveInner(String id, int cls) async {
    final stored = (await _store.list()).where((i) => i.id == id).firstOrNull;
    if (stored == null) return null; // already saved, removed, or cleared
    final p = stored.parsed!;
    final db = await _database();
    // An airtime item may only go into the category of its own kind. A stale sheet
    // (or a bad caller) that names the other one saves nothing; the item keeps waiting.
    if (p.sourceType == SmsSourceType.airtime && cls != await _airtimeCategoryFor(p.airtimeOther)) {
      return null;
    }
    int? rowId;
    if (!await TransactionDao.mpesaCodeExists(db, code: p.code)) {
      final draft = _draftFor(p, await _captureIdentity(), cls);
      final input = draft.toInput(
        cashCode: '',
        rawParseSource: 'SMS_PARSE',
        occurredAtMillis: p.transactionOccurredAt,
      );
      try {
        rowId = await TransactionDao.insert(db, input);
      } on DatabaseException catch (e) {
        // The code index refused a second row: it is already recorded.
        if (!e.isUniqueConstraintError()) rethrow;
      }
      if (rowId != null) {
        final key = draft.counterpartyKey;
        if (key.isNotEmpty) {
          try {
            await CounterpartyDao.upsertOnConfirm(db,
                sourceType: draft.type, counterpartyKey: key, classificationId: cls);
          } catch (_) {
            // The transaction is committed; the memory of the choice is a bonus.
          }
        }
        _onSaved();
      }
    }
    await _store.remove(id);
    try {
      await _bridge.ackHeld(id, generation: await _bridge.readGeneration());
    } catch (_) {
      // The held copy is dropped by the next ingest (saved code).
    }
    _held.remove(id);
    return rowId;
  }

  /// The Add screen's own draft, filled the way Add fills it after a paste
  /// (same field mapping), so the row is built by `AddDraft.toInput`.
  static AddDraft _draftFor(ParsedSmsFields p, bool capture, int classificationId) {
    final agent = p.agentNumber;
    final agentOk = agent == null || AddDraft.agentNumberOk(agent);
    return AddDraft(
      src: 'MPESA',
      type: p.sourceType.dbValue,
      captureIdentity: capture,
      amountText: (p.amountCents / 100).toStringAsFixed(2),
      feeText: (p.transactionCostCents / 100).toStringAsFixed(2),
      codeText: p.code,
      nameText: p.counterpartyLabel ?? '',
      subText: p.counterpartyPhone ?? p.paybillAccountNumber ?? (agentOk ? (agent ?? '') : ''),
      codeDuplicate: false,
      classificationId: classificationId,
    );
  }
}

/// What [RealWaitingRepository.recordChip] did (see there).
class ChipRecordResult {
  const ChipRecordResult({required this.active, this.rowId});
  final bool active;
  final int? rowId;
}
