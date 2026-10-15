// WD3 (0.1.2 S8a): the Safaricom agent-withdrawal fee reference file.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/fees/safaricom_withdrawal_fees.dart';

int? _fee(int ksh) => suggestedWithdrawalFee(ksh * 100);

void main() {
  test('constants: as-of date, source, confirmed', () {
    expect(kWithdrawalFeesAsOf, '04-08-2026');
    expect(RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(kWithdrawalFeesAsOf), isTrue);
    expect(kWithdrawalFeeSource, 'Safaricom consumer tariffs page');
    expect(kWithdrawalFeesConfirmed, isTrue);
  });

  test('bands are contiguous: no gaps, no overlaps, start 50, end 250,000', () {
    expect(kWithdrawalFeeBands.length, 14);
    expect(kWithdrawalFeeBands.first.fromKsh, 50);
    expect(kWithdrawalFeeBands.last.toKsh, 250000);
    for (var i = 0; i < kWithdrawalFeeBands.length; i++) {
      final b = kWithdrawalFeeBands[i];
      expect(b.fromKsh <= b.toKsh, isTrue);
      if (i > 0) expect(b.fromKsh, kWithdrawalFeeBands[i - 1].toKsh + 1);
    }
  });

  test('fees never fall as the amount rises', () {
    for (var i = 1; i < kWithdrawalFeeBands.length; i++) {
      expect(kWithdrawalFeeBands[i].feeKsh >= kWithdrawalFeeBands[i - 1].feeKsh, isTrue);
    }
  });

  test('every boundary', () {
    expect(_fee(49), isNull);
    expect(_fee(50), 1100);
    expect(_fee(100), 1100);
    expect(_fee(101), 2900);
    expect(_fee(2500), 2900);
    expect(_fee(2501), 5200);
    expect(_fee(3500), 5200);
    expect(_fee(3501), 6900);
    expect(_fee(5000), 6900);
    expect(_fee(5001), 8700);
    expect(_fee(7500), 8700);
    expect(_fee(7501), 11500);
    expect(_fee(10000), 11500);
    expect(_fee(10001), 16700);
    expect(_fee(15000), 16700);
    expect(_fee(15001), 18500);
    expect(_fee(20000), 18500);
    expect(_fee(20001), 19700);
    expect(_fee(35000), 19700);
    expect(_fee(35001), 27800);
    expect(_fee(50000), 27800);
    expect(_fee(50001), 30900);
    expect(_fee(250000), 30900);
    expect(_fee(250001), isNull);
  });

  test('every band edge matches its band fee (table read back)', () {
    for (final b in kWithdrawalFeeBands) {
      expect(_fee(b.fromKsh), b.feeKsh * 100);
      expect(_fee(b.toKsh), b.feeKsh * 100);
    }
  });

  test('100 shillings gives 11', () {
    expect(suggestedWithdrawalFee(10000), 1100);
  });

  test('non-whole-shilling, zero and negative amounts give null', () {
    expect(suggestedWithdrawalFee(10050), isNull);
    expect(suggestedWithdrawalFee(10001), isNull);
    expect(suggestedWithdrawalFee(0), isNull);
    expect(suggestedWithdrawalFee(-10000), isNull);
  });

  test('feeCheck returns a mismatching parsed fee UNCHANGED', () {
    final c = feeCheck(10000, 1500);
    expect(c.parsedFeeCents, 1500);
    expect(c.usualFeeCents, 1100);
    expect(c.looksUsual, isFalse);
    expect(feeLooksUsual(10000, 1500), isFalse);
  });

  test('feeCheck: the usual fee looks usual; a zero fee on 100 does not', () {
    expect(feeLooksUsual(10000, 1100), isTrue);
    expect(feeCheck(10000, 0).parsedFeeCents, 0);
    expect(feeLooksUsual(10000, 0), isFalse);
  });

  test('feeCheck: no usual fee known means nothing to contradict', () {
    final c = feeCheck(500000000, 123);
    expect(c.usualFeeCents, isNull);
    expect(c.looksUsual, isTrue);
    expect(c.parsedFeeCents, 123);
  });
}
