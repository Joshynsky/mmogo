// In-memory auto-read waiting repository and the five signed data sets' WAITING
// rows (Typical, 5 waiting, 99+ counts, Long list, Empty). Invented data copied
// from ui-rework/notifications.html; ages are moved inside the 24 h held window.
import 'dart:async';

import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/model/waiting_repository.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

/// A valid held id from a number (32 lowercase hex).
String heldIdFor(int n) => n.toRadixString(16).padLeft(32, '0');

/// Invented parsed fields (mock `T` table), [i] picks the row.
ParsedSmsFields sampleFields(int i, DateTime occurredAt) {
  switch (i % 6) {
    case 0:
      return _f('SAMPLE0A$i', SmsSourceType.sendMoney, 64000, 0, 'Sample Shop', '0700000000', occurredAt);
    case 1:
      return _f('SAMPLE1B$i', SmsSourceType.sendMoney, 120000, 0, 'Sample Pharmacy', '0700000001', occurredAt);
    case 2:
      return _f('SAMPLE2C$i', SmsSourceType.airtime, 10000, 0, 'Sample Network', null, occurredAt);
    case 3:
      return _f('SAMPLE3D$i', SmsSourceType.payBill, 230000, 0, 'Sample Power Co', null, occurredAt,
          account: '123456');
    case 4:
      return _f('SAMPLE4E$i', SmsSourceType.buyGoods, 45000, 0, 'Sample Grocer', null, occurredAt);
    default:
      return _f('SAMPLE5F$i', SmsSourceType.sendMoney, 300000, 3000, 'Sample Person', '0700000002', occurredAt);
  }
}

ParsedSmsFields _f(String code, SmsSourceType t, int amount, int cost, String label, String? phone,
        DateTime at, {String? account}) =>
    ParsedSmsFields(
      code: code,
      sourceType: t,
      amountCents: amount,
      transactionCostCents: cost,
      counterpartyLabel: label,
      counterpartyPhone: phone,
      paybillAccountNumber: account,
      transactionOccurredAt: at.millisecondsSinceEpoch,
    );

enum WaitingDataSet { typical, fiveWaiting, many, long, empty }

/// The WAITING rows of a signed data set at [now]. [failOnParse] of the result
/// is the oldest readable ready item (the one the mock cannot read).
class WaitingSetData {
  final List<WaitingItem> items;
  final Set<String> failOnParse;
  const WaitingSetData(this.items, this.failOnParse);
}

WaitingSetData waitingSet(WaitingDataSet set, DateTime now) {
  var n = 1;
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  WaitingItem ready(int minutes, {WaitingKind kind = WaitingKind.readyToParse}) =>
      WaitingItem(id: heldIdFor(n++), kind: kind, heldAt: ago(minutes));
  WaitingItem cat(int minutes, int ti, {bool flag = false}) {
    final at = ago(minutes);
    return WaitingItem(
      id: heldIdFor(n++),
      kind: WaitingKind.waitingCategory,
      heldAt: at,
      parsed: sampleFields(ti, at),
      sameCodeDifferentDetails: flag,
    );
  }

  final items = <WaitingItem>[];
  switch (set) {
    case WaitingDataSet.typical:
      // Ready: 2 h, 12 h, and the oldest (20 h, expires in 4 h) that cannot be read.
      items
        ..add(ready(120))
        ..add(ready(720))
        ..add(ready(1200))
        // A message that is gone (past the window).
        ..add(ready(3000, kind: WaitingKind.gone))
        ..add(cat(25, 0))
        ..add(cat(90, 1, flag: true))
        ..add(cat(300, 2));
    case WaitingDataSet.fiveWaiting:
      for (final a in const [10, 45, 120, 400, 900]) {
        items.add(cat(a, items.length));
      }
    case WaitingDataSet.many:
      for (var i = 1; i <= 12; i++) {
        items.add(ready(100 * i));
      }
      for (var i = 1; i <= 120; i++) {
        items.add(cat(5 * i, i));
      }
    case WaitingDataSet.long:
      for (var i = 1; i <= 8; i++) {
        items.add(ready(150 * i));
      }
      for (var i = 1; i <= 25; i++) {
        items.add(cat(20 * i, i, flag: i == 4));
      }
    case WaitingDataSet.empty:
      break;
  }
  final readyOnes = items.where((i) => i.kind == WaitingKind.readyToParse).toList()
    ..sort((a, b) => a.heldAt.compareTo(b.heldAt));
  final fail = set == WaitingDataSet.typical && readyOnes.isNotEmpty
      ? {readyOnes.first.id}
      : <String>{};
  return WaitingSetData(items, fail);
}

class FakeAutoReadWaitingRepository implements AutoReadWaitingRepository {
  FakeAutoReadWaitingRepository(
    Iterable<WaitingItem> items, {
    required this.now,
    Set<String> failOnParse = const {},
    Set<String> duplicateOnParse = const {},
  })  : _items = items.toList(),
        _failOnParse = {...failOnParse},
        _duplicateOnParse = {...duplicateOnParse};

  /// A fake loaded with a signed data set; the oldest ready item fails to parse.
  factory FakeAutoReadWaitingRepository.forSet(WaitingDataSet set, DateTime Function() now) {
    final d = waitingSet(set, now());
    return FakeAutoReadWaitingRepository(d.items, now: now, failOnParse: d.failOnParse);
  }

  final DateTime Function() now;
  final List<WaitingItem> _items;
  final Set<String> _failOnParse;
  final Set<String> _duplicateOnParse;
  final StreamController<List<WaitingItem>> _changes = StreamController.broadcast(sync: true);

  List<WaitingItem> get snapshot => List.unmodifiable(_items);

  @override
  Stream<List<WaitingItem>> watch() {
    late StreamController<List<WaitingItem>> c;
    StreamSubscription<List<WaitingItem>>? sub;
    c = StreamController<List<WaitingItem>>(
      onListen: () {
        c.add(snapshot);
        sub = _changes.stream.listen(c.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  void _emit() => _changes.add(snapshot);

  int _indexOf(String id) => _items.indexWhere((i) => i.id == id);

  @override
  Future<ParseOutcome> parse(String id) async {
    final at = _indexOf(id);
    if (at < 0) return ParseOutcome.gone;
    final item = _items[at];
    final k = effectiveKind(item, now());
    if (k == WaitingKind.gone) return ParseOutcome.gone;
    if (k != WaitingKind.readyToParse) {
      throw StateError('Only a ready item can be parsed, not $k.');
    }
    if (_duplicateOnParse.contains(id)) {
      _items.removeAt(at);
      _emit();
      return ParseOutcome.duplicate;
    }
    if (_failOnParse.contains(id)) {
      _items[at] = WaitingItem(id: id, kind: WaitingKind.unreadable, heldAt: item.heldAt);
      _emit();
      return ParseOutcome.couldNotRead;
    }
    _items[at] = WaitingItem(
      id: id,
      kind: WaitingKind.waitingCategory,
      heldAt: item.heldAt,
      parsed: sampleFields(at, item.heldAt),
    );
    _emit();
    return ParseOutcome.parsed;
  }

  @override
  Future<void> saveCategory(String id, String categoryId) async {
    final at = _indexOf(id);
    if (at < 0 || _items[at].kind != WaitingKind.waitingCategory) {
      throw StateError('No waiting-category item $id.');
    }
    _items.removeAt(at);
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    final at = _indexOf(id);
    if (at < 0) return;
    checkRemovable(_items[at], now());
    _items.removeAt(at);
    _emit();
  }
}
