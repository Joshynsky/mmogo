/// §DOMAIN.SPENT — the one rule for how much a transaction counts as
/// SPENT (0.1.2, reading A).
///
/// A cash withdrawal at an agent moves money from M-Pesa to the user's
/// pocket: it adds 0 to spent, and its transaction cost still shows in the
/// fees figure (fees are summed separately from `transaction_cost_cents`).
/// Every other type, Cash, Pochi and Airtime included, counts its full
/// amount. Both halves live here so the Dart and the SQL cannot drift; a
/// test runs them over one table on real SQLite.
library;

/// The stored `source_type` of a cash withdrawal at an agent.
const String kAgentWithdrawalType = 'AGENT_WITHDRAWAL';

/// True when [sourceType] is a cash withdrawal at an agent.
bool isWithdrawal(String sourceType) => sourceType == kAgentWithdrawalType;

/// The amount a transaction adds to "spent". [feeCents] is unused under
/// reading A and stays in the signature so reading B is a one-place edit.
int spentCents(String sourceType, int amountCents, int? feeCents) =>
    isWithdrawal(sourceType) ? 0 : amountCents;

/// Cash taken out at an agent: the amount of a withdrawal, 0 for every other
/// type. This is a separate, named figure for the Analytics Withdrawal tile.
/// It is NOT spending and is never added to a spent total.
int withdrawnCents(String sourceType, int amountCents) =>
    isWithdrawal(sourceType) ? amountCents : 0;

/// The SQL twin of [spentCents] for unaliased `transactions` columns.
const String kSpentCentsSql =
    "CASE WHEN source_type = 'AGENT_WITHDRAWAL' THEN 0 ELSE amount_cents END";

/// The same expression for a table alias, e.g. `spentCentsSqlFor('t')`.
String spentCentsSqlFor(String alias) =>
    "CASE WHEN $alias.source_type = 'AGENT_WITHDRAWAL' THEN 0 ELSE $alias.amount_cents END";
