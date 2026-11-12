/// §DOMAIN.FULIZA.DEMO — 0.2.0 S9: INVENTED Fuliza events for the UI check, behind a debug-only
/// switch. Fuliza persistence is held (schema change, slice 12), so until then the page and the Home
/// line run on [InMemoryFulizaRepository] and, in a normal build, there is NO data and NO line.
///
/// The switch is a compile-time define, off unless given: `--dart-define=MMOGO_FULIZA_DEMO=true`.
/// It is also ignored in a release build. Nothing here is real data.
library;

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'fuliza_repository.dart';

const String _demoDefine = String.fromEnvironment('MMOGO_FULIZA_DEMO');

/// True only in a debug/profile build started with the define. A release build is always false.
bool get fulizaDemoOn => _demoDefine.isNotEmpty && !kReleaseMode;

/// Codes of the invented ordinary payments the demo events pair with (seeded by the demo seed).
const demoFulizaCodes = ['QDMFL00001', 'QDMFL00002', 'QDMFL00003', 'QDMFL00004'];

/// Five events, newest 1 day ago: a first borrowing with a balance carried in, a daily-fee gap, a partial
/// repayment, a borrowing and a last partial repayment. Owing ends at about Ksh 1,227.00 (an estimate,
/// because the last message is a partial repayment).
List<FulizaEvent> demoFulizaEvents(DateTime now) {
  DateTime at(int daysAgo, int h, int m) {
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
    return DateTime(d.year, d.month, d.day, h, m);
  }

  return [
    FulizaEvent(
      kind: FulizaEventKind.draw,
      code: 'QDMFL00001',
      at: at(6, 10, 2),
      amountCents: 60000,
      feeCents: 600,
      printedTotalCents: 80600, // 200 carried in + 600 + 6
    ),
    FulizaEvent(
      kind: FulizaEventKind.draw,
      code: 'QDMFL00002',
      at: at(3, 15, 20),
      amountCents: 40000,
      feeCents: 400,
      printedTotalCents: 121600, // 806 + 404 + 6 daily fee seen
    ),
    FulizaEvent(kind: FulizaEventKind.repayPartial, code: 'QDMFL00003', at: at(2, 9, 0), amountCents: 30000),
    FulizaEvent(
      kind: FulizaEventKind.draw,
      code: 'QDMFL00004',
      at: at(1, 18, 40),
      amountCents: 50000,
      feeCents: 500,
      printedTotalCents: 142700, // 916 + 505 + 6
    ),
    FulizaEvent(kind: FulizaEventKind.repayPartial, code: 'QDMFL00005', at: at(1, 21, 10), amountCents: 20000),
  ];
}
