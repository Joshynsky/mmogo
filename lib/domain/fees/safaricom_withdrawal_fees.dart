/// §DOMAIN.FEES — Safaricom's usual agent-withdrawal charge (0.1.2 S8a, WD3).
///
/// The ONE place the tariff lives. Agent withdrawals by registered customers
/// only (the ATM table is single-source and no ATM type exists). If Safaricom
/// changes its tariff, only this file changes.
///
/// Evidence (RL3): the table was confirmed band for band against Safaricom's
/// own consumer tariffs page, last updated 04-08-2026 (research 06-10-2026,
/// `safaricom-tariff-page-and-airtime-shapes-2026-10-06.md`). The PM or
/// Operations may re-check the page later.
///
/// Used as a SANITY REFERENCE only: a parsed fee is never rejected and never
/// rewritten; [suggestedWithdrawalFee] feeds a tappable hint, never a prefill.
library;

const String kWithdrawalFeesAsOf = '04-08-2026';
const String kWithdrawalFeeSource = 'Safaricom consumer tariffs page';
const bool kWithdrawalFeesConfirmed = true;

/// One band: amounts from [fromKsh] to [toKsh] inclusive cost [feeKsh].
class WithdrawalFeeBand {
  final int fromKsh;
  final int toKsh;
  final int feeKsh;
  const WithdrawalFeeBand(this.fromKsh, this.toKsh, this.feeKsh);
}

/// Contiguous, ascending, whole shillings.
const List<WithdrawalFeeBand> kWithdrawalFeeBands = [
  WithdrawalFeeBand(50, 100, 11),
  WithdrawalFeeBand(101, 500, 29),
  WithdrawalFeeBand(501, 1000, 29),
  WithdrawalFeeBand(1001, 1500, 29),
  WithdrawalFeeBand(1501, 2500, 29),
  WithdrawalFeeBand(2501, 3500, 52),
  WithdrawalFeeBand(3501, 5000, 69),
  WithdrawalFeeBand(5001, 7500, 87),
  WithdrawalFeeBand(7501, 10000, 115),
  WithdrawalFeeBand(10001, 15000, 167),
  WithdrawalFeeBand(15001, 20000, 185),
  WithdrawalFeeBand(20001, 35000, 197),
  WithdrawalFeeBand(35001, 50000, 278),
  WithdrawalFeeBand(50001, 250000, 309),
];

/// The usual fee in cents for [amountCents], or null when the amount is not a
/// whole number of shillings, is under KSh 50 or over KSh 250,000.
int? suggestedWithdrawalFee(int amountCents) {
  if (amountCents <= 0 || amountCents % 100 != 0) return null;
  final ksh = amountCents ~/ 100;
  for (final b in kWithdrawalFeeBands) {
    if (ksh >= b.fromKsh && ksh <= b.toKsh) return b.feeKsh * 100;
  }
  return null;
}

/// What a fee check says. [parsedFeeCents] is the parsed fee UNCHANGED.
class WithdrawalFeeCheck {
  final int parsedFeeCents;

  /// The usual fee, or null when the amount has no usual fee to compare.
  final int? usualFeeCents;

  /// True when the fee equals the usual one, or when there is nothing to
  /// compare (then no "fee differs" note should be shown).
  final bool looksUsual;

  const WithdrawalFeeCheck(this.parsedFeeCents, this.usualFeeCents, this.looksUsual);
}

/// Compares a parsed (or typed) fee with the usual one. Never rewrites it.
WithdrawalFeeCheck feeCheck(int amountCents, int parsedFeeCents) {
  final usual = suggestedWithdrawalFee(amountCents);
  return WithdrawalFeeCheck(
      parsedFeeCents, usual, usual == null || usual == parsedFeeCents);
}

/// True when the fee is the usual one (or no usual fee is known).
bool feeLooksUsual(int amountCents, int feeCents) =>
    feeCheck(amountCents, feeCents).looksUsual;
