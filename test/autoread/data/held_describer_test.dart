// §AUTOREAD.HELD_DESCRIBER: the repository's held-message descriptions. Invented
// bodies with a sentinel word; the sentinel must never come back, be cached,
// be logged, be written or be thrown.
@Tags(['autoread'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/autoread_bridge.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/model/held_description.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;
import '../logic/reading_fakes.dart';

const String kSentinel = 'zebraquartz';
final DateTime _t0 = DateTime(2026, 11, 13, 14, 0);

/// Bridge whose peek throws an error that carries the sentinel (a bad channel).
class _ThrowingBridge extends FakeAutoReadBridge {
  _ThrowingBridge({required super.now});
  bool boom = false;
  @override
  Future<HeldMessage?> peekHeld(String id) async {
    if (boom) throw StateError('channel failed on $kSentinel');
    return super.peekHeld(id);
  }
}

String _text(HeldDescription? d) => [d?.what, d?.code, d?.amount, d?.time].whereType<String>().join('|');

void main() {
  late Database db;
  late _ThrowingBridge bridge;
  late RealWaitingRepository repo;
  late DateTime now;

  int count(String call) => bridge.calls.where((c) => c == call).length;
  int peeks(String id) => count('peekHeld:$id');

  setUp(() async {
    now = _t0;
    SharedPreferences.setMockInitialValues({});
    ReadingControllerHolder.instance = null;
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 3,
            singleInstance: false,
            onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
            onCreate: (d, v) async {
              await AppSchema.createSchema(d);
              await AppSchema.seed(d);
            }));
    bridge = _ThrowingBridge(now: () => now);
    final store = InMemoryPendingStore();
    repo = RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(
          bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => now),
      database: () async => db,
      now: () => now,
      captureIdentity: () async => true,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
    );
  });
  tearDown(() async {
    repo.dispose();
    ReadingControllerHolder.instance = null;
    await db.close();
  });

  String hold(int n, String body, {Duration age = const Duration(hours: 1)}) {
    final id = heldIdFor(n);
    bridge.hold(id, body, now.subtract(age));
    return id;
  }

  group('what is described', () {
    test('readable: the name is always in the description, whatever "What alerts show" is', () async {
      final id = hold(1, kSampleSendMoney);
      await repo.ingest();
      expect(_text(await repo.describeHeld(id)), 'Sent Ksh 500 to JANE DOE');
      repo.clearDescriptions();
      final b = FakeReadingBridge()..alertDetails = true;
      ReadingControllerHolder.instance =
          ReadingController(bridge: b, store: FakeGenerationStore(), prefs: FakeReadingPrefs());
      expect(_text(await repo.describeHeld(id)), 'Sent Ksh 500 to JANE DOE');
    });

    test('unreadable: code, amount, time only; the words around them never', () async {
      final id = hold(2, 'UFGH123456 odd $kSentinel text Ksh 70 at 2:08 PM more $kSentinel');
      await repo.ingest();
      final d = await repo.describeHeld(id);
      expect(d?.code, 'UFGH123456');
      expect(d?.amount, 'Ksh 70');
      expect(d?.time, '14:08');
      expect(d?.what, isNull);
      expect(_text(d).contains(kSentinel), isFalse);
      expect(_text(d).contains('odd'), isFalse);
    });

    test('unreadable with nothing found, and over the length cap: no description', () async {
      final a = hold(3, 'hello there $kSentinel');
      final b = hold(4, 'UFGH123456 Ksh 70 ${'x' * 2100}');
      await repo.ingest();
      expect(await repo.describeHeld(a), isNull);
      expect(await repo.describeHeld(b), isNull);
    });

    test('a failed look (bridge throws with the sentinel in its text) is no description, quietly', () async {
      final id = hold(5, kSampleSendMoney);
      await repo.ingest();
      bridge.boom = true;
      Object? thrown;
      HeldDescription? d;
      try {
        d = await repo.describeHeld(id);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNull);
      expect(d, isNull);
      expect(bridge.isClaimed(id), isFalse);
    });

    test('an id that is not held (unknown, invalid): null and no peek', () async {
      await repo.ingest();
      expect(await repo.describeHeld(heldIdFor(99)), isNull);
      expect(await repo.describeHeld('not-an-id'), isNull);
      expect(bridge.calls.where((c) => c.startsWith('peekHeld')), isEmpty);
    });
  });

  group('nothing leaves memory', () {
    test('no print, debugPrint or Zone print; no prefs written; no file created', () async {
      final printed = <String>[];
      final oldDebug = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      final files = <String>[];
      final ok = hold(6, 'UFGH123456 $kSentinel Ksh 5');
      final good = hold(7, kSampleSendMoney);
      final bad = hold(8, kSampleSendMoney);
      await repo.ingest();
      final prefsBefore = (await SharedPreferences.getInstance()).getKeys().toSet();
      await IOOverrides.runZoned(() async {
        await runZonedGuarded(() async {
          await repo.describeHeld(ok);
          await repo.describeHeld(good);
          bridge.boom = true;
          await repo.describeHeld(bad);
          bridge.boom = false;
        }, (e, s) => printed.add('ERROR $e'),
            zoneSpecification: ZoneSpecification(print: (s, p, z, line) => printed.add(line)));
      }, createFile: (path) {
        files.add(path);
        throw StateError('no file may be created');
      }, createDirectory: (path) {
        files.add(path);
        throw StateError('no directory may be created');
      });
      debugPrint = oldDebug;
      expect(printed, isEmpty);
      expect(files, isEmpty);
      expect((await SharedPreferences.getInstance()).getKeys().toSet(), prefsBefore);
    });
  });

  group('lifetime', () {
    test('one look per id per visit; claims balanced; a second visit after clear looks again', () async {
      final id = hold(10, kSampleSendMoney);
      await repo.ingest();
      final base = peeks(id);
      await repo.describeHeld(id);
      await repo.describeHeld(id);
      await Future.wait([repo.describeHeld(id), repo.describeHeld(id)]);
      expect(peeks(id), base + 1);
      expect(count('claim:$id'), count('release:$id'));
      repo.clearDescriptions();
      await repo.describeHeld(id);
      expect(peeks(id), base + 2);
      expect(count('claim:$id'), count('release:$id'));
    });

    test('40 held messages: at most 40 looks, one after another, all released', () async {
      final ids = [for (var i = 0; i < 40; i++) hold(100 + i, kSampleSendMoney, age: Duration(minutes: i))];
      await repo.ingest();
      final before = bridge.calls.where((c) => c.startsWith('peekHeld')).length;
      await Future.wait([for (final id in ids) repo.describeHeld(id)]);
      expect(bridge.calls.where((c) => c.startsWith('peekHeld')).length - before, 40);
      for (final id in ids) {
        expect(bridge.isClaimed(id), isFalse);
      }
    });

    test('cleared on dispose', () async {
      final id = hold(11, kSampleSendMoney);
      await repo.ingest();
      await repo.describeHeld(id);
      expect(repo.describedCount, 1);
      repo.dispose();
      expect(repo.describedCount, 0);
    });

    test('Remove early drops the description with the row; no new look for it', () async {
      final id = hold(12, 'UFGH123456 Ksh 5');
      await repo.ingest();
      expect((await repo.describeHeld(id))?.code, 'UFGH123456');
      expect(repo.describedCount, 1);
      await repo.remove(id);
      expect(repo.describedCount, 0);
      final base = peeks(id);
      expect(await repo.describeHeld(id), isNull);
      expect(peeks(id), base);
    });

    test('Parse drops the description; an expired message gives none and no peek', () async {
      final id = hold(13, kSampleSendMoney);
      final old = hold(14, kSampleSendMoney, age: const Duration(hours: 23, minutes: 30));
      await repo.ingest();
      await repo.describeHeld(id);
      await repo.describeHeld(old);
      expect(repo.describedCount, 2);
      await repo.parse(id);
      expect(repo.describedCount, 1);
      now = now.add(const Duration(hours: 1));
      final base = peeks(old);
      expect(await repo.describeHeld(old), isNull);
      expect(peeks(old), base);
      await repo.ingest();
      expect(repo.describedCount, 0);
    });

    test('Delete data: the held messages go, the next refresh leaves no description', () async {
      final id = hold(15, kSampleSendMoney);
      await repo.ingest();
      await repo.describeHeld(id);
      await bridge.ackHeld(id, generation: 1); // what deleting held messages does on the phone side
      await repo.ingest();
      expect(repo.describedCount, 0);
      expect(await repo.describeHeld(id), isNull);
    });
  });

  group('race with Parse', () {
    test('Parse tapped while a look holds the claim: Parse parses, never gone', () async {
      final id = hold(20, kSampleSendMoney);
      await repo.ingest();
      final gate = Completer<void>();
      bridge.peekGate = gate.future;
      final look = repo.describeHeld(id);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.isClaimed(id), isTrue); // the look holds the claim now
      final parse = repo.parse(id);
      gate.complete();
      expect(await parse, ParseOutcome.parsed);
      expect((await look)?.what, 'Sent Ksh 500 to JANE DOE');
      expect(bridge.isClaimed(id), isFalse);
      expect(repo.itemById(id)?.kind, WaitingKind.waitingCategory);
    });

    test('describe asked after Parse started: no description', () async {
      final id = hold(21, kSampleSendMoney);
      await repo.ingest();
      final gate = Completer<void>();
      bridge.peekGate = gate.future;
      final parse = repo.parse(id);
      await Future<void>.delayed(Duration.zero);
      final look = repo.describeHeld(id);
      gate.complete();
      expect(await parse, ParseOutcome.parsed);
      expect(await look, isNull);
    });

    test('Details tap while a look runs: Parse still never gone (the Details look is queued too)', () async {
      final id = hold(22, kSampleSendMoney);
      await repo.ingest();
      final gate = Completer<void>();
      bridge.peekGate = gate.future;
      final details = repo.detailsFor(id);
      await Future<void>.delayed(Duration.zero);
      final parse = repo.parse(id);
      gate.complete();
      expect(await parse, ParseOutcome.parsed);
      await details;
    });
  });
}
