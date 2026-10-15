import '../../../data/db/transaction_dao.dart';
import '../../../domain/counterparty/counterparty_key.dart';
import '../../../domain/format/ksh_amount.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../widgets/ksh_input_formatter.dart';

/// §ADD.DRAFT — a plain snapshot of what the Add form holds right now, and
/// every rule derived from it (amounts, the identity values that would be
/// saved, the counterparty key, whether Review is allowed, the hint under the
/// button, the review-sheet row labels). No widgets, no database: the screen
/// builds one from its controllers on each use, so the rules can be tested
/// without pumping a page. Moved out of `add_screen.dart` (0.1.2 S8c-1 step 0)
/// with the same behaviour.
class AddDraft {
  const AddDraft({
    required this.src,
    required this.type,
    required this.captureIdentity,
    required this.amountText,
    required this.feeText,
    required this.codeText,
    required this.nameText,
    required this.subText,
    required this.codeDuplicate,
    required this.classificationId,
  });

  /// `'MPESA'` or `'CASH'`.
  final String src;

  /// A `transactions.source_type` value; meaningless while [src] is `'CASH'`.
  final String type;
  final bool captureIdentity;
  final String amountText;
  final String feeText;
  final String codeText;
  final String nameText;
  final String subText;
  final bool codeDuplicate;
  final int? classificationId;

  static final RegExp _codeShapeRe = RegExp(r'^[A-Z0-9]{10}$');

  bool get isCash => src == 'CASH';

  /// An M-Pesa Withdrawal entry (never while the Cash tab is showing).
  bool get isWithdrawal => !isCash && type == 'AGENT_WITHDRAWAL';

  /// An M-Pesa Airtime entry: no Fee field, no receiver, a locked category.
  bool get isAirtime => !isCash && type == 'AIRTIME';

  /// Withdrawal and Airtime use their built-in category and show no chips.
  bool get hasFixedCategory => isWithdrawal || isAirtime;

  /// The built-in category of a locked type, by `seed_key`; null otherwise.
  static String? fixedSeedKey(String type) => switch (type) {
        'AGENT_WITHDRAWAL' => 'AGENT_WITHDRAWAL:cash_withdrawal',
        'AIRTIME' => 'AIRTIME:airtime',
        _ => null,
      };

  static final RegExp _agentNumberRe = RegExp(r'^[0-9]{1,20}$');

  /// True when [text] is a storable agent number (digits only, 1..20).
  static bool agentNumberOk(String text) => _agentNumberRe.hasMatch(text);

  static bool codeShapeOk(String code) => _codeShapeRe.hasMatch(code.trim());

  bool get codeValidShape => codeShapeOk(codeText);

  int? get amountCents => parseKshCents(stripKshGrouping(amountText));

  /// An empty Fee is `0`, not invalid (2026-09-19 PM decision), EXCEPT for a
  /// Withdrawal, where it is mandatory (empty = null, a typed `0` is fine).
  /// Airtime has no Fee field: a parsed fee is kept, anything unreadable is 0.
  int? get feeCents {
    final text = feeText.trim();
    if (isAirtime) return text.isEmpty ? 0 : (parseKshCents(text, allowZero: true) ?? 0);
    if (text.isEmpty) return isWithdrawal ? null : 0;
    return parseKshCents(text, allowZero: true);
  }

  /// The inline Fee error, or null. Shown for a Withdrawal's empty Fee only
  /// once the field was [touched]; a bad value shows at once; never for
  /// Airtime or Cash.
  String? feeError({required bool touched}) {
    if (isCash || isAirtime) return null;
    final text = feeText.trim();
    if (text.isNotEmpty && parseKshCents(text, allowZero: true) == null) {
      return 'Enter a cost from 0 to 10,000,000.00';
    }
    if (isWithdrawal && text.isEmpty && touched) return kWithdrawalFeeRequiredText;
    return null;
  }

  String? get effectiveLabel {
    if (!captureIdentity || isAirtime) return null; // Airtime never carries a label
    final t = nameText.trim();
    return t.isEmpty ? null : t;
  }

  String? get effectivePhone {
    if (type != 'SEND_MONEY' || !captureIdentity) return null;
    final t = subText.trim();
    return t.isEmpty ? null : t;
  }

  /// `transactions.agent_number`: Withdrawal only, tick on, digits only 1..20.
  /// Anything else is null, so a bad value can never reach
  /// [TransactionDao.checkAgentNumber].
  String? get effectiveAgentNumber {
    if (!isWithdrawal || !captureIdentity) return null;
    final t = subText.trim();
    return agentNumberOk(t) ? t : null;
  }

  String? get effectiveAccount {
    if (type != 'PAYBILL' || !captureIdentity) return null;
    final t = subText.trim();
    return t.isEmpty ? null : t;
  }

  SmsSourceType get smsSourceType => switch (type) {
        'SEND_MONEY' => SmsSourceType.sendMoney,
        'PAYBILL' => SmsSourceType.payBill,
        'BUY_GOODS' => SmsSourceType.buyGoods,
        'POCHI_LA_BIASHARA' => SmsSourceType.pochi,
        'AGENT_WITHDRAWAL' => SmsSourceType.agentWithdrawal,
        'AIRTIME' => SmsSourceType.airtime,
        _ => throw StateError('AddDraft.type must be a non-cash source type, got "$type"'),
      };

  /// The single derivation call site shared by the read path (fed to
  /// `category_chips.dart`) and the write path (`_save`'s
  /// `CounterpartyDao.upsertOnConfirm` call) — same discipline
  /// `mpesa_tab_body.dart` established, carried forward unchanged.
  String get counterpartyKey {
    if (isCash) return '';
    switch (smsSourceType) {
      case SmsSourceType.sendMoney:
        final phone = effectivePhone;
        if (phone == null || phone.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);
      case SmsSourceType.payBill:
        final label = effectiveLabel;
        final account = effectiveAccount;
        if (label == null || label.isEmpty || account == null || account.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.payBill, counterpartyLabel: label, paybillAccountNumber: account);
      case SmsSourceType.buyGoods:
        final label = effectiveLabel;
        if (label == null || label.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: label);
      case SmsSourceType.pochi:
      case SmsSourceType.agentWithdrawal:
      case SmsSourceType.airtime:
        return ''; // these types never learn a receiver
    }
  }

  bool get identityPairComplete {
    if (isCash) return true; // Cash has no receiver fields (`type` is only the M-Pesa side's)
    if (type == 'SEND_MONEY' && captureIdentity) {
      return nameText.trim().isNotEmpty && subText.trim().isNotEmpty;
    }
    if (type == 'PAYBILL' && captureIdentity) {
      return nameText.trim().isNotEmpty && subText.trim().isNotEmpty;
    }
    return true;
  }

  /// Build step 7: "disabled until there is an amount, a valid code
  /// (M-Pesa) and a category."
  List<String> get missing {
    final miss = <String>[];
    if (amountCents == null) miss.add('an amount');
    if (!isCash && !codeValidShape) miss.add('the 10-character code');
    if (classificationId == null) miss.add('a category');
    return miss;
  }

  bool get canReview => missing.isEmpty && !(!isCash && codeDuplicate) && identityPairComplete && feeCents != null;

  /// What "Also record the receiver's name & phone" still needs (Send Money:
  /// name + phone; Paybill: business + account). Empty when the box is off,
  /// for Buy Goods and for Cash, or when both are filled.
  List<String> get missingIdentity {
    if (identityPairComplete) return const [];
    final (first, second) = type == 'PAYBILL'
        ? ('the business name', 'the account number')
        : ('the receiver’s name', 'the receiver’s phone');
    final noName = nameText.trim().isEmpty;
    final noSub = subText.trim().isEmpty;
    if (noName && noSub) {
      return [type == 'PAYBILL' ? 'the business name and account number' : 'the receiver’s name and phone'];
    }
    return [if (noName) first, if (noSub) second];
  }

  String get reviewHint {
    if (!isCash && codeDuplicate) return 'That code is already recorded.';
    final identity = missingIdentity;
    final miss = [
      ...missing,
      ...identity,
      if (feeCents == null) (isWithdrawal && feeText.trim().isEmpty ? 'the fee' : 'a valid fee'),
    ];
    if (miss.isEmpty) return '';
    final list = miss.length == 1 ? miss.first : '${miss.sublist(0, miss.length - 1).join(', ')} and ${miss.last}';
    // The box is what asks for them, so say how to skip it too.
    return identity.isEmpty ? 'Add $list.' : 'Add $list, or untick “Also record the receiver’s name & phone”.';
  }

  String get typeLabel => switch (isCash ? 'CASH' : type) {
        'SEND_MONEY' => 'Send Money',
        'PAYBILL' => 'Paybill',
        'BUY_GOODS' => 'Buy Goods',
        'POCHI_LA_BIASHARA' => 'Pochi',
        'AGENT_WITHDRAWAL' => 'Withdrawal',
        'AIRTIME' => 'Airtime',
        _ => 'Cash',
      };

  String get counterpartyFieldLabel => switch (type) {
        'PAYBILL' => 'Business',
        'BUY_GOODS' => 'Shop',
        'AGENT_WITHDRAWAL' => 'Agent',
        _ => 'To',
      };

  /// Mock's `aReview.onclick`: `if (m && !A.who) rows.push(['Receiver', 'Not
  /// recorded (private)'])` — a distinct, generic label from the per-type
  /// one used when a name WAS captured. Airtime and Cash have no receiver row.
  /// Send Money, Paybill and Buy Goods keep today's rule (no row when nothing
  /// was captured); Pochi and Withdrawal always show a row ("Not recorded").
  String? get reviewCounterpartyRowLabel {
    if (isCash || isAirtime) return null;
    if (!captureIdentity) return 'Receiver';
    if (_alwaysShowsReceiverRow) return counterpartyFieldLabel;
    return nameText.trim().isEmpty ? null : counterpartyFieldLabel;
  }

  bool get _alwaysShowsReceiverRow => type == 'POCHI_LA_BIASHARA' || type == 'AGENT_WITHDRAWAL';

  String? get reviewCounterpartyRowValue {
    if (isCash || isAirtime) return null;
    if (!captureIdentity) return 'Not recorded (private)';
    final name = nameText.trim();
    final sub = isWithdrawal ? (effectiveAgentNumber ?? '') : subText.trim();
    if (_alwaysShowsReceiverRow) {
      final parts = [if (name.isNotEmpty) name.toUpperCase(), if (sub.isNotEmpty) sub];
      return parts.isEmpty ? 'Not recorded' : parts.join(' · ');
    }
    if (name.isEmpty) return null;
    return sub.isEmpty ? name.toUpperCase() : '${name.toUpperCase()} · $sub';
  }

  /// The row the database gets, built the one way for the screen and the
  /// tests. [cashCode] is the generated `CASH-...` code for a Cash entry.
  NewTransactionInput toInput({
    required String cashCode,
    required String rawParseSource,
    required int occurredAtMillis,
  }) {
    return NewTransactionInput(
      displayCode: isCash ? cashCode : codeText.trim(),
      sourceType: isCash ? 'CASH' : type,
      amountCents: amountCents!,
      transactionCostCents: isCash ? null : feeCents,
      counterpartyLabel: isCash ? null : effectiveLabel,
      counterpartyPhone: isCash ? null : effectivePhone,
      paybillAccountNumber: isCash ? null : effectiveAccount,
      agentNumber: isCash ? null : effectiveAgentNumber,
      classificationId: classificationId!,
      rawParseSource: isCash ? 'MANUAL' : rawParseSource,
      transactionOccurredAt: occurredAtMillis,
    );
  }
}

/// The signed Withdrawal fee-required text (brief addendum E).
const String kWithdrawalFeeRequiredText = 'Enter the fee. It can be 0 if you were not charged.';
