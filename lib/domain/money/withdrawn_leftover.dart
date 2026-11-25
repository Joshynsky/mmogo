/// §DOMAIN.LEFTOVER — the cash withdrawn that is not yet counted (0.2.2, F1).
///
/// Cash spent out of a withdrawal is a Cash entry linked to it
/// (`parent_transaction_id`); it is already in the Cash bar. What is left of
/// the withdrawal, taken out of M-Pesa and not accounted for, is the leftover.
/// It is worked out PER withdrawal and never goes below 0: a withdrawal that
/// is over-linked (more cash entries than it) must not eat the leftover of a
/// different withdrawal. Home hides its row when the sum is 0.
library;

/// One withdrawal's leftover: [withdrawnCents] minus [linkedCents], never negative.
int withdrawalLeftoverCents(int withdrawnCents, int linkedCents) {
  final w = withdrawnCents < 0 ? 0 : withdrawnCents;
  final l = linkedCents < 0 ? 0 : linkedCents;
  return l >= w ? 0 : w - l;
}

/// The leftovers of several withdrawals, added. Each pair is
/// (amount withdrawn, total of the Cash entries linked to it).
int totalWithdrawalLeftoverCents(
  Iterable<(int withdrawn, int linked)> withdrawals,
) => withdrawals.fold<int>(
  0,
  (sum, w) => sum + withdrawalLeftoverCents(w.$1, w.$2),
);
