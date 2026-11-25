// F1 (0.2.2): the Home "Cash withdrawn, not counted" figure. Invented amounts, in cents.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/money/withdrawn_leftover.dart';

void main() {
  group('withdrawalLeftoverCents', () {
    test('nothing linked: the whole withdrawal is left', () {
      expect(withdrawalLeftoverCents(100000, 0), 100000);
    });
    test('partly linked: the difference (the PM example, 1,000 withdrawn, 800 spent)', () {
      expect(withdrawalLeftoverCents(100000, 80000), 20000);
    });
    test('fully linked: zero, so the row is hidden', () {
      expect(withdrawalLeftoverCents(100000, 100000), 0);
    });
    test('over-linked: never negative', () {
      expect(withdrawalLeftoverCents(100000, 100001), 0);
      expect(withdrawalLeftoverCents(100000, 900000), 0);
    });
    test('zero withdrawal and bad (negative) inputs stay at zero or ignore the negative part', () {
      expect(withdrawalLeftoverCents(0, 0), 0);
      expect(withdrawalLeftoverCents(0, 500), 0);
      expect(withdrawalLeftoverCents(-5, 0), 0);
      expect(withdrawalLeftoverCents(1000, -50), 1000);
    });
  });

  group('totalWithdrawalLeftoverCents', () {
    test('no withdrawals: zero', () {
      expect(totalWithdrawalLeftoverCents(const []), 0);
    });
    test('several withdrawals add up (1,000 and 1,500, 1,800 spent in all as 1,000 + 800 gives 700)', () {
      expect(totalWithdrawalLeftoverCents(const [(100000, 100000), (150000, 80000)]), 70000);
    });
    test('an over-linked withdrawal does not eat the leftover of another one', () {
      expect(totalWithdrawalLeftoverCents(const [(100000, 150000), (50000, 0)]), 50000);
    });
    test('all spent: zero', () {
      expect(totalWithdrawalLeftoverCents(const [(100000, 100000), (50000, 50000)]), 0);
    });
  });
}
