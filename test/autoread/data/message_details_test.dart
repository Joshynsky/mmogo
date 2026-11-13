// §AUTOREAD.MESSAGE_DETAILS (0.2.0 S4): pure rules of the Details sheet and the
// repository's one-time look. Invented messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/message_details.dart';
import 'package:mmogo/autoread/model/held_description.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/message_details_sheet.dart';
import 'package:mmogo/autoread/ui/unreadable_copy.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 3, 14, 5);

void main() {
  group('exactTimeLeft / clock / received', () {
    final exp = DateTime(2026, 11, 3, 18, 0);
    test('hours and minutes', () {
      expect(exactTimeLeft(exp, DateTime(2026, 11, 3, 13, 48)), '4 h 12 min');
      expect(exactTimeLeft(exp, DateTime(2026, 11, 3, 14, 0)), '4 h');
      expect(exactTimeLeft(exp, DateTime(2026, 11, 3, 17, 23)), '37 min');
    });
    test('a day or more keeps whole hours', () {
      expect(timeLeftWords(const Duration(hours: 24)), '24 h');
      expect(timeLeftWords(const Duration(hours: 23, minutes: 59)), '23 h 59 min');
    });
    test('under a minute and none left', () {
      expect(exactTimeLeft(exp, DateTime(2026, 11, 3, 17, 59, 30)), 'less than 1 min');
      expect(exactTimeLeft(exp, exp), 'none left');
      expect(exactTimeLeft(exp, exp.add(const Duration(hours: 1))), 'none left');
    });
    test('clock and received day', () {
      expect(clockText(DateTime(2026, 11, 3, 9, 5)), '09:05');
      expect(receivedText(DateTime(2026, 11, 3, 0, 1), DateTime(2026, 11, 3, 23, 0)), 'Today, 00:01');
      expect(receivedText(DateTime(2026, 11, 2, 22, 10), DateTime(2026, 11, 3, 8, 0)), 'Yesterday, 22:10');
      expect(receivedText(DateTime(2026, 10, 31, 9, 0), DateTime(2026, 11, 3, 8, 0)), '3 days ago, 09:00');
    });
  });

  group('buildMessageDetails', () {
    WaitingItem held(WaitingKind k, Duration age) =>
        WaitingItem(id: heldIdFor(1), kind: k, heldAt: _t0.subtract(age));

    test('unreadable: sender, code, amount, time, time left; Not found for gaps; no body words', () {
      final d = buildMessageDetails(held(WaitingKind.unreadable, const Duration(minutes: 20)), _t0,
          light: const HeldDescription(code: 'QWE1R2T3Y4', amount: 'Ksh 5'));
      expect(d.valueOf(kDetailsSenderLabel), 'MPESA');
      expect(d.valueOf(kUnreadableCodeLabel), 'QWE1R2T3Y4');
      expect(d.valueOf(kDetailsAmountLabel), 'Ksh 5');
      expect(d.valueOf(kUnreadableTimeLabel), kNotFound);
      expect(d.valueOf(kDetailsTimeLeftLabel), '23 h 40 min (expires at 13:45 tomorrow)');
      expect(d.valueOf('First words'), isNull);
      expect(d.valueOf('What failed'), isNull);
      expect(d.note, kUnreadablePasteWithCode);
      expect(d.fine, kUnreadableFine);
    });

    test('expired held item reads as gone', () {
      final d = buildMessageDetails(held(WaitingKind.readyToParse, const Duration(hours: 1)), _t0, expired: true);
      expect(d.kind, WaitingKind.gone);
      expect(d.valueOf(kDetailsStatusLabel), kDetailsExpiredValue);
      expect(d.valueOf(kDetailsTimeLeftLabel), isNull);
    });
  });

  group('repository detailsFor', () {
    late Database db;
    late FakeAutoReadBridge bridge;
    late RealWaitingRepository repo;
    var now = _t0;

    setUp(() async {
      now = _t0;
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
      bridge = FakeAutoReadBridge(now: () => now);
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
      await db.close();
    });

    test('a ready message: amount, type, name, exact time left; nothing stored or acked; no code', () async {
      final id = heldIdFor(1);
      bridge.hold(id, kSampleSendMoney, _t0.subtract(const Duration(minutes: 20)));
      await repo.ingest();
      final d = (await repo.detailsFor(id))!;
      expect(d.valueOf(kDetailsAmountLabel), 'Ksh 500');
      expect(d.valueOf(kDetailsUnderstoodLabel), 'Send Money, JANE DOE');
      expect(d.valueOf(kDetailsTimeLeftLabel), '23 h 40 min (expires at 13:45 tomorrow)');
      expect(bridge.isHeld(id), isTrue);
      expect(bridge.isClaimed(id), isFalse);
      final all = d.lines.map((l) => l.value).join('|') + (d.note ?? '');
      expect(all.contains('QWE1R2T3Y4'), isFalse);
      expect(all.contains('0712345678'), isFalse);
    });

    test('an unreadable message: code, amount and time only, never its words', () async {
      final id = heldIdFor(2);
      bridge.hold(id, 'XYZ1234567 Confirmed. something odd about KSH 77 for JOHN',
          _t0.subtract(const Duration(hours: 2)));
      await repo.ingest();
      final d = (await repo.detailsFor(id))!;
      expect(d.kind, WaitingKind.unreadable);
      expect(d.valueOf(kUnreadableCodeLabel), 'XYZ1234567');
      expect(d.valueOf(kDetailsAmountLabel), 'Ksh 77');
      expect(d.valueOf(kUnreadableTimeLabel), kNotFound);
      final text = d.lines.map((l) => l.value).join('|') + (d.note ?? '') + (d.fine ?? '');
      expect(text.contains('something'), isFalse);
      expect(text.contains('JOHN'), isFalse);
      expect(d.valueOf(kDetailsTimeLeftLabel), '22 h (expires at 12:05 tomorrow)');
    });

    test('a message past the window reads as gone; an unknown id is null', () async {
      final id = heldIdFor(3);
      bridge.hold(id, kSampleSendMoney, _t0.subtract(const Duration(hours: 3)));
      await repo.ingest();
      now = _t0.add(const Duration(hours: 25));
      final d = (await repo.detailsFor(id))!;
      expect(d.kind, WaitingKind.gone);
      expect(await repo.detailsFor(heldIdFor(99)), isNull);
    });
  });

  testWidgets('sheet shows the lines and a Close button; a missing row says so', (t) async {
    Widget host(MessageDetails? d) => AppPaletteScope(
          controller: AppPaletteController('ocean', 'light'),
          child: MaterialApp(home: Scaffold(body: MessageDetailsSheet(details: d))),
        );
    await t.pumpWidget(host(const MessageDetails(
        kind: WaitingKind.readyToParse, lines: [DetailLine('Sender', 'MPESA')], note: 'quiet note')));
    expect(find.text('Message details'), findsOneWidget);
    expect(find.text('MPESA'), findsOneWidget);
    expect(find.text('quiet note'), findsOneWidget);
    expect(find.byKey(const Key('detailsClose')), findsOneWidget);
    await t.pumpWidget(host(null));
    expect(find.text(kDetailsMissing), findsOneWidget);
  });
}
