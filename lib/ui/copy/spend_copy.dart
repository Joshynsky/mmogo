import '../../domain/format/money.dart';

/// Shared wording for money that is tracked but not counted as spending
/// (a cash withdrawal at an agent). Used by Home's recent rows; the Analytics
/// list rows move onto it in S6.
///
/// "not counted as spending, only the fee of Ksh X" when the row has a fee,
/// else "not counted as spending". Screen-reader text; never printed on a row.
String notCountedLabel({int feeCents = 0}) => feeCents > 0
    ? 'not counted as spending, only the fee of ${formatKsh(feeCents)}'
    : 'not counted as spending';
