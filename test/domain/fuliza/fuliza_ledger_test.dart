// 0.2.0 slice 3: Fuliza pairing, opening balance, owing-unknown, fee estimate.
// Fixtures A-E are the invented ones in fuliza-cycle-study section 5. Nothing real.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/fuliza/fuliza_ledger.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/domain/parsing/fuliza_parser.dart';

final _t0 = DateTime(2026, 11, 1, 9, 0);
DateTime _at(int minutes, {int days = 0}) => _t0.add(Duration(days: days, minutes: minutes));

FulizaDraw _draw(String code, int draw, int fee, int total) => FulizaDraw(
      code: code,
      drawCents: draw,
      feeCents: fee,
      printedTotalCents: total,
      dueDate: DateTime(2026, 11, 14),
      feeWordingIsAccessFee: false,
    );

FulizaRepayment _repay(String code, int amount, {required bool full}) =>
    FulizaRepayment(code: code, amountCents: amount, isFull: full, availableLimitCents: null);

void main() {
  late InMemoryFulizaRepository repo;
  late FulizaLedger ledger;
  setUp(() {
    repo = InMemoryFulizaRepository();
    ledger = FulizaLedger(repo);
  });

  group('pairing by code', () {
    test('pair found: payment first, then the draw', () async {
      repo.addPaymentCode('PAY0000001');
      await ledger.ingest(_draw('PAY0000001', 10000, 100, 10100), _at(0));
      final s = await ledger.state();
      expect(s.current!.draws.single.paired, isTrue);
    });

    test('pair found: draw first, then the payment arrives later', () async {
      await ledger.ingest(_draw('PAY0000002', 10000, 100, 10100), _at(0));
      expect((await ledger.state()).current!.draws.single.paired, isFalse);
      repo.addPaymentCode('PAY0000002');
      expect((await ledger.state()).current!.draws.single.paired, isTrue);
    });

    test('pair missing: stays waiting for its payment; other codes do not pair', () async {
      repo.addPaymentCode('OTHER00001');
      await ledger.ingest(_draw('PAY0000003', 10000, 100, 10100), _at(0));
      expect((await ledger.state()).current!.draws.single.paired, isFalse);
    });

    test('a spend with no draw leaves the ledger empty', () async {
      repo.addPaymentCode('PAY0000004');
      final s = await ledger.state();
      expect(s.chains, isEmpty);
      expect(s.owingCents, isNull);
    });

    test('the same draw read twice is stored once (dedupe on code + kind)', () async {
      final d = _draw('PAY0000005', 10000, 100, 10100);
      expect(await ledger.ingest(d, _at(0)), isTrue);
      expect(await ledger.ingest(d, _at(1)), isFalse);
      expect((await repo.events()).length, 1);
    });
  });

  group('fixture A: clean 0-to-paid cycle', () {
    test('opening 0, balance 101.00 then 0.00, fees 1.00, residual 0', () async {
      await ledger.ingest(_draw('AAAAAAAAA1', 10000, 100, 10100), _at(0));
      var s = await ledger.state();
      expect(s.owingCents, 10100);
      expect(s.owingIsEstimate, isFalse);
      expect(s.current!.openingCents, 0);
      expect(s.current!.carriedIn, isFalse);
      expect(s.current!.feeCents, 100);
      expect(s.current!.draws.single.residualCents, 0);
      await ledger.ingest(_repay('AAAAAAAAA2', 10100, full: true), _at(60));
      s = await ledger.state();
      expect(s.owingCents, 0);
      expect(s.current!.closed, isTrue);
      expect(s.current!.dailyFeeEstimateCents, 0);
      expect(s.current!.unreconciledCents, 0);
    });
  });

  group('fixture B: partial and a following draw', () {
    test('owing about 408.00 after the partial, re-based by the next draw, ends at 0', () async {
      await ledger.ingest(_draw('BBBBBBBBB1', 50000, 500, 50500), _at(0));
      await ledger.ingest(_draw('BBBBBBBBB2', 30000, 300, 80800), _at(10));
      await ledger.ingest(_repay('BBBBBBBBB3', 40000, full: false), _at(20));
      var s = await ledger.state();
      expect(s.owingCents, 40800);
      expect(s.owingIsEstimate, isTrue);
      await ledger.ingest(_draw('BBBBBBBBB4', 5000, 50, 45850), _at(30));
      s = await ledger.state();
      expect(s.owingCents, 45850);
      expect(s.owingIsEstimate, isFalse);
      expect(s.current!.draws.last.residualCents, 0);
      await ledger.ingest(_repay('BBBBBBBBB5', 45850, full: true), _at(40));
      s = await ledger.state();
      expect(s.owingCents, 0);
      expect(s.current!.unreconciledCents, 0);
      expect(s.current!.dailyFeeEstimateCents, 0);
    });
  });

  group('fixture C: daily fee residual', () {
    test('later-day draw: residual +6.00 shown as estimated daily fee', () async {
      await ledger.ingest(_draw('CCCCCCCCC1', 120000, 1200, 121200), _at(0));
      await ledger.ingest(_draw('CCCCCCCCC2', 10000, 100, 131900), _at(0, days: 1));
      final s = await ledger.state();
      final d = s.current!.draws.last;
      expect(d.residualCents, 600);
      expect(d.needsReview, isFalse);
      expect(s.dailyFeeEstimateCents, 600);
      await ledger.ingest(_repay('CCCCCCCCC3', 131900, full: true), _at(5, days: 1));
      expect((await ledger.state()).owingCents, 0);
      expect((await ledger.state()).dailyFeeEstimateCents, 600);
    });

    test('variant: no day-2 draw, the 6.00 shows from the full repayment amount', () async {
      await ledger.ingest(_draw('CCCCCCCCD1', 120000, 1200, 121200), _at(0));
      await ledger.ingest(_repay('CCCCCCCCD2', 121800, full: true), _at(0, days: 1));
      final s = await ledger.state();
      expect(s.dailyFeeEstimateCents, 600);
      expect(s.owingCents, 0);
    });

    test('full repayment below the running balance is unreconciled, not invented', () async {
      await ledger.ingest(_draw('CCCCCCCCE1', 10000, 100, 10100), _at(0));
      await ledger.ingest(_repay('CCCCCCCCE2', 10000, full: true), _at(5));
      final s = await ledger.state();
      expect(s.current!.unreconciledCents, 100);
      expect(s.dailyFeeEstimateCents, 0);
    });

    test('a negative residual with no explanation is flagged for review', () async {
      await ledger.ingest(_draw('CCCCCCCCF1', 10000, 100, 10100), _at(0));
      await ledger.ingest(_draw('CCCCCCCCF2', 10000, 100, 10200), _at(5));
      final d = (await ledger.state()).current!.draws.last;
      expect(d.residualCents, -10000);
      expect(d.needsReview, isTrue);
    });
  });

  group('fixture D: hidden opening balance', () {
    test('first draw seen prints 627.10: opening 617.00 carried in', () async {
      await ledger.ingest(_draw('DDDDDDDDD1', 1000, 10, 62710), _at(0));
      final s = await ledger.state();
      expect(s.current!.openingCents, 61700);
      expect(s.current!.carriedIn, isTrue);
      expect(s.owingCents, 62710);
    });

    test('first draw after a gap of a year or more starts a new chain, carried in', () async {
      await ledger.ingest(_draw('DDDDDDDDE1', 10000, 100, 10100), _at(0));
      await ledger.ingest(_repay('DDDDDDDDE2', 10100, full: true), _at(30));
      await ledger.ingest(_draw('DDDDDDDDE3', 1000, 10, 62710), _at(0, days: 449));
      final s = await ledger.state();
      expect(s.chains.length, 2);
      expect(s.current!.carriedIn, isTrue);
      expect(s.current!.openingCents, 61700);
      expect(s.current!.draws.single.residualCents, 0);
    });

    test('an unclosed chain followed by a long gap does not carry its balance forward', () async {
      await ledger.ingest(_draw('DDDDDDDDF1', 10000, 100, 10100), _at(0));
      await ledger.ingest(_draw('DDDDDDDDF2', 1000, 10, 20110), _at(0, days: 60));
      final s = await ledger.state();
      expect(s.chains.length, 2);
      expect(s.current!.openingCents, 19100);
      expect(s.current!.draws.single.needsReview, isFalse);
    });
  });

  group('fixture E: partial first and out-of-order partial', () {
    test('partial first: owing unknown until the next draw prints a total', () async {
      await ledger.ingest(_repay('EEEEEEEEE1', 10000, full: false), _at(0));
      var s = await ledger.state();
      expect(s.owingUnknown, isTrue);
      expect(s.owingCents, isNull);
      await ledger.ingest(_draw('EEEEEEEEE2', 2000, 20, 54020), _at(60));
      s = await ledger.state();
      expect(s.owingCents, 54020);
      expect(s.owingUnknown, isFalse);
      expect(s.owingIsEstimate, isFalse);
    });

    test('partial first, then a full repayment: owing 0', () async {
      await ledger.ingest(_repay('EEEEEEEEF1', 10000, full: false), _at(0));
      await ledger.ingest(_repay('EEEEEEEEF2', 5000, full: true), _at(30));
      final s = await ledger.state();
      expect(s.owingCents, 0);
      expect(s.owingUnknown, isFalse);
    });

    test('out-of-order partial is not subtracted twice', () async {
      // balance 500.00; the network applies a 100.00 partial, then the draw
      // 400.00 + 4.00 prints 804.00; the partial message is delivered after.
      await ledger.ingest(_draw('EEEEEEEEG1', 49500, 500, 50000), _at(0));
      await ledger.ingest(_draw('EEEEEEEEG2', 40000, 400, 80400), _at(10));
      var s = await ledger.state();
      expect(s.current!.draws.last.needsReview, isTrue); // residual -100.00 so far
      await ledger.ingest(_repay('EEEEEEEEG3', 10000, full: false), _at(12));
      s = await ledger.state();
      expect(s.owingCents, 80400);
      expect(s.owingIsEstimate, isFalse);
      expect(s.current!.draws.last.needsReview, isFalse);
      expect(s.current!.draws.last.explainedByLaterPartial, isTrue);
      await ledger.ingest(_repay('EEEEEEEEG4', 80400, full: true), _at(30));
      s = await ledger.state();
      expect(s.owingCents, 0);
      expect(s.current!.unreconciledCents, 0);
      expect(s.current!.dailyFeeEstimateCents, 0);
    });

    test('a partial of a different size than the residual is a normal partial', () async {
      await ledger.ingest(_draw('EEEEEEEEH1', 49500, 500, 50000), _at(0));
      await ledger.ingest(_draw('EEEEEEEEH2', 40000, 400, 80400), _at(10));
      await ledger.ingest(_repay('EEEEEEEEH3', 7000, full: false), _at(12));
      final s = await ledger.state();
      expect(s.owingCents, 73400);
      expect(s.owingIsEstimate, isTrue);
      expect(s.current!.draws.last.needsReview, isTrue);
    });
  });

  group('rule 9 and ordering', () {
    test('notices and unrecognised text change nothing; a limit notice sets the limit', () async {
      expect(await ledger.ingest(const FulizaUnrecognised(), _at(0)), isFalse);
      expect(
          await ledger.ingest(
              const FulizaFailedNotice(kind: FulizaFailedKind.outstandingRequest), _at(1)),
          isFalse);
      expect(await ledger.ingest(const FulizaLimitNotice(limitCents: 250000), _at(2)), isFalse);
      final s = await ledger.state();
      expect(s.chains, isEmpty);
      expect(s.limitCents, 250000);
    });

    test('events inserted out of time order are computed in time order', () async {
      await ledger.ingest(_repay('FFFFFFFFF2', 10100, full: true), _at(60));
      await ledger.ingest(_draw('FFFFFFFFF1', 10000, 100, 10100), _at(0));
      final s = await ledger.state();
      expect(s.owingCents, 0);
      expect(s.current!.closed, isTrue);
    });

    test('parser to ledger end to end (invented text)', () async {
      const text = 'AB12CD34EF Confirmed. Fuliza M-PESA amount is Ksh 100.00. Interest charged '
          'Ksh 1.00. Total Fuliza M-PESA outstanding amount is Ksh 101.00 due on 14/11/26.';
      await ledger.ingest(FulizaParser.parse(text), _at(0));
      expect((await ledger.state()).owingCents, 10100);
    });
  });
}
