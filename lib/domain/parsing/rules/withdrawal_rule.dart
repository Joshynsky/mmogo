import '../parsed_sms_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.WITHDRAWAL — agent cash withdrawal (0.1.2 S8a, WD2).
///
/// Invented shape: `ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw
/// Ksh2,000.00 from 1234567 - SAMPLE AGENT NAME  New M-PESA balance is
/// Ksh4,100.00. Transaction cost, Ksh29.00. ...`
///
/// Anchored on `Withdraw Ksh<amt> from <digits> - <text>`; whitespace tolerant
/// (the real message glues "Confirmed.on" and "AMWithdraw" and has a double
/// space before "New"). The fee is MANDATORY: no readable
/// `Transaction cost, Ksh<fee>` means not understood, never 0 (a printed 0.00 is fine). The agent
/// text runs up to "New M-PESA balance" (or the fee line, or the end), is
/// whitespace collapsed and capped at [kAgentTextMaxChars] characters.
const int kAgentTextMaxChars = 200;

class WithdrawalRule {
  WithdrawalRule._();

  static final RegExp _re = RegExp(
    r'^([A-Z0-9]{10})\s*Confirmed\.\s*on\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern\\s*'
    r'Withdraw\s+Ksh([\d,]+\.\d{2})\s+from\s+(\d{1,20})\s+-\s+'
    r'([\s\S]+?)\s*(?=New M-PESA balance|Transaction cost,|$)'
    '[\\s\\S]*?$kFeePattern',
  );

  static ParsedSmsFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    var agent = normalizeLabel(m.group(6)!);
    if (agent.isEmpty) return null;
    if (agent.length > kAgentTextMaxChars) {
      agent = agent.substring(0, kAgentTextMaxChars).trimRight();
    }
    return ParsedSmsFields(
      code: m.group(1)!,
      sourceType: SmsSourceType.agentWithdrawal,
      amountCents: parseAmountCents(m.group(4)!),
      counterpartyLabel: agent,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      agentNumber: m.group(5)!,
      transactionOccurredAt: parseOccurredAt(m.group(2)!, m.group(3)!),
      transactionCostCents: parseMoneyCents(m.group(7)!),
    );
  }
}
