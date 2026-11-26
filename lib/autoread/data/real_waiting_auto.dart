/// §AUTOREAD.REAL_WAITING_AUTO — airtime auto-record, queued Yes import and Undo for RealWaitingRepository
/// (J2 / 0.2.1; split out 0.2.2). A part of real_waiting_repository.dart; no behaviour change.
part of 'real_waiting_repository.dart';

extension RealWaitingAutoRecord on RealWaitingRepository {
  // ------------------------------------------------- airtime auto-record (J2)


  /// The ACTIVE built-in Airtime category of a kind, found by seed key, or null
  /// (then nothing is recorded for that kind and the item waits as today; never a
  /// fallback to the other category).
  Future<int?> _airtimeCategoryFor(bool other) async {
    final row = await ClassificationDao.fetchActiveBySeedKey(await _database(), seedKey: airtimeSeedKey(other));
    return row?.id;
  }

  /// With a switch ON, records every parsed Airtime item of THAT kind that waits
  /// (the user tapped Parse for each). Never touches another type or the other
  /// kind. Inside [_locked].
  Future<void> _autoRecordPending() async {
    if (!airtime.on && !airtime.onOther) return;
    try {
      final stored = (await _store.list())
          .where((i) => isAutoRecordEligible(i, myselfOn: airtime.on, otherOn: airtime.onOther))
          .toList();
      for (final item in stored) {
        final cls = await _airtimeCategoryFor(item.parsed!.airtimeOther);
        if (cls == null) {
          _stuck.add(item.id);
          continue;
        }
        final rowId = await _saveInner(item.id, cls);
        if (rowId == null) {
          _stuck.add(item.id);
        } else {
          _stuck.remove(item.id);
          await _markAutomatic(rowId);
          final at = _now();
          final shown = await _trailStore.add(rowId, at); // never throws; a failed write keeps the record
          await _reloadTrail(shown);
          airtime.noteRecorded(AutoRecorded(
              rowId: rowId, amountCents: item.parsed!.amountCents, at: at, airtimeOther: item.parsed!.airtimeOther));
        }
      }
    } catch (_) {
      // A failure leaves the item waiting; the user can still Categorize it.
      for (final i in await _store.list().catchError((_) => <WaitingItem>[])) {
        if (isAutoRecordEligible(i, myselfOn: airtime.on, otherOn: airtime.onOther)) _stuck.add(i.id);
      }
    }
  }

  // ------------------------------------------- queued Yes (Ask first, 0.2.1)

  /// Records the Yes taps queued on phone alerts while the app was closed, then refreshes the category names
  /// the alert shows. Inside [_locked]. Never throws; a failure leaves the items waiting.
  Future<void> _importQueuedYes() async {
    if (!_queuedYesOn) return;
    try {
      await _importQueuedYesWork().timeout(kQueuedYesBudget);
    } catch (_) {
      // Too slow or failed: the ingest goes on; a mark stays and is tried again at the next ingest.
    }
  }

  Future<void> _importQueuedYesWork() async {
    try {
      final items = await _store.list();
      // The payee names, read before the import removes the recorded items (the no-tap message names them).
      final payee = {for (final i in items) i.id: i.parsed?.counterpartyLabel};
      final recorded = await _queuedYes.run(items);
      if (recorded.isNotEmpty) {
        for (final r in recorded) {
          await _noteTrail(r.rowId);
        }
        final cb = _onQueuedYes;
        if (cb != null) {
          cb(recorded);
        } else {
          showQueuedYesToasts([for (final r in recorded) if (!r.automatic) r], undoQueuedYes);
          // 0.2.2 B2d: rows Auto-record wrote (no tap); Undo = the same soft delete, and the person STAYS on
          // Auto-record (D-U, reverses S-3; the ledger hook leaves the rule alone). The message gets the plain
          // payee name (no digits, hard_rule_arrival_toast.dart) and the category's name.
          final auto = [for (final r in recorded) if (r.automatic) r];
          if (auto.isNotEmpty) {
            final labels = autoArrivalLabels(payee, await _categoryNamesOf({for (final r in auto) r.categoryId}));
            showAutoArrivalToasts(auto, undoQueuedYes, nameOf: labels.nameOf, categoryOf: labels.categoryOf);
          }
        }
      }
    } catch (_) {}
    await _refreshCategoryNames();
  }

  /// Category id -> name for [ids] (empty when they cannot be read; the message then shows its placeholder).
  Future<Map<int, String>> _categoryNamesOf(Set<int> ids) async {
    try {
      final rows = await (await _database())
          .rawQuery('SELECT id, name FROM classifications WHERE id IN (${List.filled(ids.length, '?').join(',')})', [...ids]);
      return {for (final r in rows) if (r['id'] is int && r['name'] is String) r['id'] as int: r['name'] as String};
    } catch (_) {
      return const {};
    }
  }

  Future<bool> _categoryActive(int id) async => (await (await _database())
          .rawQuery('SELECT 1 FROM classifications WHERE id = ? AND active = 1', [id]))
      .isNotEmpty;

  /// Keeps the Kotlin alert's category names current (written only when they changed).
  Future<void> _refreshCategoryNames() async {
    try {
      if (!await anyAskFirstRuleStored()) return; // no alert will ask a question: no names needed
      final rows = await (await _database()).rawQuery('SELECT id, name FROM classifications WHERE active = 1');
      final names = {for (final r in rows) if (r['id'] is int && r['name'] is String) r['id'] as int: r['name'] as String};
      if (names.length == _namesWritten.length && names.entries.every((e) => _namesWritten[e.key] == e.value)) return;
      await CategoryNameCache().write(names);
      _namesWritten = names;
    } catch (_) {}
  }

  /// Undo of one entry recorded from a queued Yes: Recently deleted (restorable for 1 hour). A row already
  /// deleted or gone is left alone.
  Future<void> undoQueuedYes(QueuedYesRecorded e) => _locked(() async {
        final db = await _database();
        final row = (await db.query('transactions', columns: ['deleted_at'], where: 'id = ?', whereArgs: [e.rowId]))
            .firstOrNull;
        if (row != null && row['deleted_at'] == null) {
          await TransactionDao.softDelete(db, id: e.rowId);
          _onSaved();
        }
        await _reloadTrail();
      });

  /// Marks the row "Recorded automatically" (0.2.1 on; older rows stay unmarked). The database only
  /// allows it on a non-Cash row from an SMS parse; a refusal leaves the row recorded, unmarked.
  Future<void> _markAutomatic(int rowId) async {
    try {
      await TransactionDao.markRecordedAutomatically(await _database(), id: rowId);
    } catch (_) {}
  }

  /// The switch for airtime for another number (default OFF); same behaviour.
  Future<void> setAirtimeAutoOther(bool on) => _locked(() async {
        await _writeAirtimeAutoOther(on);
        airtime.setOnOther(on);
        await _autoRecordPending();
        await _publish();
      });

  /// The switch: remembers the choice; turning it ON records the Airtime items
  /// that already wait (same type the user just agreed to).
  Future<void> setAirtimeAuto(bool on) => _locked(() async {
        await _writeAirtimeAuto(on);
        airtime.setOn(on);
        await _autoRecordPending();
        await _publish();
      });

  /// Shows the stored trail: [entries] (just written) or a fresh read, joined
  /// to the ledger. A failure leaves the list as it was.
  Future<void> _reloadTrail([List<TrailEntry>? entries]) async {
    try {
      airtime.setTrail(await joinTrail(await _database(), entries ?? await _trailStore.load()));
    } catch (_) {}
  }

  /// Undo of one auto-recorded entry: it moves to Recently deleted (the
  /// existing soft delete, restorable for 1 hour) and leaves every total.
  /// The row is read first: one already in Recently deleted, or gone, is left
  /// alone (a second Undo must not move its 1 hour window).
  Future<void> undoAutoRecord(AutoRecorded e) => _locked(() async {
        final db = await _database();
        final row = (await db.query('transactions', columns: ['deleted_at'], where: 'id = ?', whereArgs: [e.rowId]))
            .firstOrNull;
        if (row != null && row['deleted_at'] == null) {
          await TransactionDao.softDelete(db, id: e.rowId);
          _onSaved();
        }
        await _reloadTrail();
      });

}

Future<bool> _prefsReadAirtimeAuto() async =>
    (await SharedPreferences.getInstance()).getBool(kAirtimeAutoPrefKey) ?? false;

Future<void> _prefsWriteAirtimeAuto(bool on) async =>
    (await SharedPreferences.getInstance()).setBool(kAirtimeAutoPrefKey, on);

Future<bool> _prefsReadAirtimeAutoOther() async =>
    (await SharedPreferences.getInstance()).getBool(kAirtimeAutoOtherPrefKey) ?? false;

Future<void> _prefsWriteAirtimeAutoOther(bool on) async =>
    (await SharedPreferences.getInstance()).setBool(kAirtimeAutoOtherPrefKey, on);
