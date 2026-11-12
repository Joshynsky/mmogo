/// §DOMAIN.PARSING.FULIZA — Fuliza message parser (0.2.0 slice 2, pure Dart).
///
/// A SIBLING of [SmsParser], not part of its payment chain: every consumer of
/// `ParseResult.success` treats it as "a payment to categorize", and a Fuliza
/// draw or repayment is not one. Nothing is wired to it yet (no AutoReadService,
/// no Kotlin, no database): slice 3 pairs the results, a later slice stores them.
///
/// RULES (fuliza-cycle-study section 3, rule 1):
///  - Only the exact wordings below match. The bare word "Fuliza" matches
///    nothing: adverts inside ordinary messages ("Opt in to FULIZA") carry it.
///  - A draw accepts both "Interest charged" and "Access Fee charged".
///  - Any other shape, or a value that cannot be read (zero draw, 31/2/26),
///    returns [FulizaUnrecognised]. [FulizaParser.parse] NEVER throws.
///
/// Invented shapes in the tests only; no real text, code or number is kept here.
library;

import 'rules/parse_helpers.dart';

/// What the parser made of one message.
sealed class FulizaMessage {
  const FulizaMessage();
}

/// `CODE Confirmed. Fuliza M-PESA amount is Ksh X. Interest charged Ksh F.
/// Total Fuliza M-PESA outstanding amount is Ksh T due on dd/mm/yy`.
/// The message has no time of its own: the caller supplies the receive time.
class FulizaDraw extends FulizaMessage {
  const FulizaDraw({
    required this.code,
    required this.drawCents,
    required this.feeCents,
    required this.printedTotalCents,
    required this.dueDate,
    required this.feeWordingIsAccessFee,
  });

  final String code;
  final int drawCents;
  final int feeCents;

  /// "Total Fuliza M-PESA outstanding amount": the figure that always wins.
  final int printedTotalCents;
  final DateTime dueDate;

  /// True for the "Access Fee charged" wording, false for "Interest charged".
  final bool feeWordingIsAccessFee;
}

/// `Ksh X from your M-PESA has been used to fully|partially pay your
/// outstanding Fuliza M-PESA`. A partial prints NO amount still owed.
class FulizaRepayment extends FulizaMessage {
  const FulizaRepayment({
    required this.code,
    required this.amountCents,
    required this.isFull,
    required this.availableLimitCents,
  });

  final String code;
  final int amountCents;
  final bool isFull;

  /// "Available Fuliza M-PESA limit is Ksh L", or null if the message omits it.
  final int? availableLimitCents;
}

/// `your Fuliza M-PESA limit is KSH L`. Standalone, no code, no ledger effect;
/// may update the limit that is shown.
class FulizaLimitNotice extends FulizaMessage {
  const FulizaLimitNotice({required this.limitCents});
  final int limitCents;
}

enum FulizaFailedKind {
  /// "Failed. Insufficient funds ... as well as Fuliza ... Available Fuliza limit KSH L"
  insufficientFunds,

  /// "Failed ... register for the M-PESA overdraw Services Fuliza"
  notOptedIn,

  /// "Dear Customer, you have an outstanding Fuliza M-PESA transaction, please
  /// try again later": a refusal, proof that a draw can be pending.
  outstandingRequest,
}

/// A failed or refused request. No amount owed, no code, no ledger effect.
class FulizaFailedNotice extends FulizaMessage {
  const FulizaFailedNotice({required this.kind, this.availableLimitCents});
  final FulizaFailedKind kind;

  /// Only the insufficient-funds shape prints a limit.
  final int? availableLimitCents;
}

/// Not a Fuliza ledger or notice shape (including adverts that name Fuliza).
class FulizaUnrecognised extends FulizaMessage {
  const FulizaUnrecognised();
}

class FulizaParser {
  FulizaParser._();

  /// `Ksh 500.00`, `Ksh500.00`, `KSH 1,000.00`.
  static const String _money = r'Ksh\.?\s?([\d,]+\.\d{2})';

  static final RegExp _draw = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s*Fuliza M-PESA amount is\s+' + _money +
    r'\.?\s*(Interest|Access Fee) charged\s+' + _money +
    r'\.?\s*Total Fuliza M-PESA outstanding amount is\s+' + _money +
    r'\s+due on\s+' + kDatePattern,
    caseSensitive: false,
  );

  static final RegExp _repay = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s*' + _money +
    r'\s+from your M-PESA has been used to (fully|partially) pay your outstanding Fuliza M-PESA',
    caseSensitive: false,
  );

  static final RegExp _availableLimit =
      RegExp(r'Available Fuliza(?: M-PESA)? limit(?: is)?\s+' + _money, caseSensitive: false);

  static final RegExp _limitNotice = RegExp(
    r'your Fuliza M-PESA limit is\s+' + _money + r'\.?\s*Keep using M-PESA to grow your limit',
    caseSensitive: false,
  );

  static final RegExp _failedInsufficient = RegExp(
    r'^Failed\b[\s\S]*?\bas well as Fuliza\b',
    caseSensitive: false,
  );

  static final RegExp _failedNotOptedIn = RegExp(
    r'^Failed\b[\s\S]*?register for the M-PESA overdraw Services Fuliza',
    caseSensitive: false,
  );

  static final RegExp _outstanding = RegExp(
    r'^Dear Customer,\s*you have an outstanding Fuliza M-PESA transaction,\s*please try again later',
    caseSensitive: false,
  );

  /// Never throws: any problem becomes [FulizaUnrecognised].
  static FulizaMessage parse(String? text) {
    try {
      if (text == null) return const FulizaUnrecognised();
      final t = text.trim();
      if (t.isEmpty || t.length > 2000) return const FulizaUnrecognised();
      return _parse(t) ?? const FulizaUnrecognised();
    } catch (_) {
      return const FulizaUnrecognised();
    }
  }

  static FulizaMessage? _parse(String t) {
    final d = _draw.firstMatch(t);
    if (d != null) {
      return FulizaDraw(
        code: d.group(1)!.toUpperCase(),
        drawCents: parseAmountCents(d.group(2)!),
        feeCents: parseMoneyCents(d.group(4)!),
        printedTotalCents: parseMoneyCents(d.group(5)!),
        dueDate: _dueDate(d.group(6)!),
        feeWordingIsAccessFee: d.group(3)!.toLowerCase() == 'access fee',
      );
    }
    final r = _repay.firstMatch(t);
    if (r != null) {
      final lim = _availableLimit.firstMatch(t.substring(r.end));
      return FulizaRepayment(
        code: r.group(1)!.toUpperCase(),
        amountCents: parseAmountCents(r.group(2)!),
        isFull: r.group(3)!.toLowerCase() == 'fully',
        availableLimitCents: lim == null ? null : parseMoneyCents(lim.group(1)!),
      );
    }
    final l = _limitNotice.firstMatch(t);
    if (l != null) return FulizaLimitNotice(limitCents: parseMoneyCents(l.group(1)!));
    if (_outstanding.hasMatch(t)) {
      return const FulizaFailedNotice(kind: FulizaFailedKind.outstandingRequest);
    }
    if (_failedNotOptedIn.hasMatch(t)) {
      return const FulizaFailedNotice(kind: FulizaFailedKind.notOptedIn);
    }
    if (_failedInsufficient.hasMatch(t)) {
      final lim = _availableLimit.firstMatch(t);
      return FulizaFailedNotice(
        kind: FulizaFailedKind.insufficientFunds,
        availableLimitCents: lim == null ? null : parseMoneyCents(lim.group(1)!),
      );
    }
    return null;
  }

  /// `dd/mm/yy` to a local date; an impossible date throws (caught by [parse]).
  static DateTime _dueDate(String s) {
    final p = s.split('/').map(int.parse).toList();
    final year = p[2] < 100 ? p[2] + 2000 : p[2];
    final at = DateTime(year, p[1], p[0]);
    if (at.year != year || at.month != p[1] || at.day != p[0]) {
      throw FormatException('Not a real date: $s');
    }
    return at;
  }
}
