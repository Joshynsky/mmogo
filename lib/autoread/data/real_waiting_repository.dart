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
/// notification tap. A timer on the next expiry re-emits so the bell numbers
/// drop without a user action. All state changes run one after another.
///
/// Save order (see [saveCategory]): transaction first, then the waiting item
/// leaves, then the held copy is acked. A crash between any two steps leaves
/// either the item (retry is a no-op for the transaction) or nothing.
library;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/app_database.dart';
import '../../data/db/counterparty_dao.dart';
import '../../data/db/transaction_dao.dart';
import '../../data/prefs/app_prefs.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/screens/add/add_draft.dart';
import '../bridge/autoread_bridge.dart';
import '../held_window.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';
import '../service/autoread_service.dart';
import '../ui/category_choices.dart';
import 'pending_items_store.dart';
import 'real_category_choices.dart';

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
  })  : _bridge = bridge,
        _store = store,
        _service = service,
        _database = database ?? (() => AppDatabase.instance.database),
        _now = now ?? DateTime.now,
        _captureIdentity = captureIdentity ?? AppPrefs.readCaptureIdentityPreference,
        _onSaved = onSaved ?? (() {}),
        _timerFactory = timer ?? Timer.new;

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

  final Map<String, _Held> _held = {};
  List<WaitingItem> _current = const [];
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
      ...stored,
      for (final e in _held.entries) WaitingItem(id: e.key, kind: e.value.kind, heldAt: e.value.heldAt),
    ]);
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
    _closed = true;
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
                break;
            }
          } catch (_) {
            // One bad message must not stop the others; it is looked at again next time.
          }
        }
      }
      await _publish();
      if (!_ready.isCompleted) _ready.complete();
    });
  }

  /// The row with this id in the latest list, or null.
  WaitingItem? itemById(String id) => _current.where((i) => i.id == id).firstOrNull;

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

  /// The categories the Categorize sheet offers for [item] (the same ones Add
  /// shows for its type).
  Future<CategoryChoices> categoryChoicesFor(WaitingItem item) async {
    final type = item.parsed?.sourceType;
    if (type == null) throw StateError('Only a parsed item can be categorized.');
    return RealCategoryChoices(await _database(), type);
  }

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
        final stored = (await _store.list()).where((i) => i.id == id).firstOrNull;
        if (stored == null) return; // already saved, removed, or cleared
        final p = stored.parsed!;
        final db = await _database();
        if (!await TransactionDao.mpesaCodeExists(db, code: p.code)) {
          final draft = _draftFor(p, await _captureIdentity(), cls);
          final input = draft.toInput(
            cashCode: '',
            rawParseSource: 'SMS_PARSE',
            occurredAtMillis: p.transactionOccurredAt,
          );
          var inserted = false;
          try {
            await TransactionDao.insert(db, input);
            inserted = true;
          } on DatabaseException catch (e) {
            // The code index refused a second row: it is already recorded.
            if (!e.isUniqueConstraintError()) rethrow;
          }
          if (inserted) {
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
        await _publish();
      });

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
