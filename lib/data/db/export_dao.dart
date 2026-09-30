import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One row of the CSV export query — CSV export has no table of its own
/// (2026-09-17): it is a read-only
/// `transactions JOIN classifications JOIN classification_groups` query,
/// columns including `counterparty_phone` alongside the pre-existing
/// `counterparty_label`/`paybill_account_number`, filtered
/// `deleted_at IS NULL`.
class ExportTransactionRow {
  const ExportTransactionRow({
    required this.displayCode,
    required this.sourceType,
    required this.amountCents,
    required this.transactionCostCents,
    required this.counterpartyLabel,
    required this.counterpartyPhone,
    required this.paybillAccountNumber,
    required this.classificationName,
    required this.groupDisplayName,
    required this.occurredAt,
  });

  final String displayCode;
  final String sourceType; // 'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'
  final int amountCents;

  /// Always `null` for CASH rows (schema CHECK); NOT NULL for every other
  /// `source_type`.
  final int? transactionCostCents;
  final String? counterpartyLabel;
  final String? counterpartyPhone;
  final String? paybillAccountNumber;
  final String classificationName;
  final String groupDisplayName;
  final DateTime occurredAt;
}

/// T10 — CSV Export's query + formatting layer. Follows the same raw-SQL-
/// against-`AppDatabase` idiom `analytics_dao.dart`/`home_dashboard_dao.dart`
/// already established for this project (no repository/ORM abstraction).
///
/// Column set (this dispatch's own disclosed judgment call — the spec
/// doesn't enumerate exact columns, only the join/filter/mechanism): Date,
/// Type, Classification Group, Classification, Counterparty Label,
/// Counterparty Phone, Paybill Account Number, Amount (KES), Transaction
/// Cost (KES), M-Pesa/Cash Code — a reasonable, PM-usable export covering
/// every identity field the spec calls out plus enough classification/
/// amount detail to be useful in a spreadsheet without also allocating time
/// figures the PM never asked for.
class ExportDao {
  ExportDao._();

  static const List<String> csvHeader = [
    'Date',
    'Type',
    'Classification Group',
    'Classification',
    'Counterparty Label',
    'Counterparty Phone',
    'Paybill Account Number',
    'Amount (KES)',
    'Transaction Cost (KES)',
    'M-Pesa/Cash Code',
  ];

  /// Count of active (non-soft-deleted) transactions — backs the Export CSV
  /// button's enabled/disabled state (disabled when there are
  /// no active transactions) without fetching/joining full rows
  /// just to answer "is there anything to export".
  static Future<int> activeTransactionCount(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM transactions WHERE deleted_at IS NULL',
    );
    return (rows.first['cnt'] as num).toInt();
  }

  /// The governing query itself: `transactions JOIN classifications JOIN
  /// classification_groups`, `deleted_at IS NULL`, most-recent-first (same
  /// ordering convention every other read query in this codebase uses).
  static Future<List<ExportTransactionRow>> activeTransactions(Database db) async {
    final rows = await db.rawQuery('''
      SELECT t.display_code, t.source_type, t.amount_cents, t.transaction_cost_cents,
             t.counterparty_label, t.counterparty_phone, t.paybill_account_number,
             c.name AS classification_name, g.display_name AS group_display_name,
             t.transaction_occurred_at
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      JOIN classification_groups g ON g.id = c.group_id
      WHERE t.deleted_at IS NULL
      ORDER BY t.transaction_occurred_at DESC
    ''');
    return rows
        .map(
          (row) => ExportTransactionRow(
            displayCode: row['display_code'] as String,
            sourceType: row['source_type'] as String,
            amountCents: (row['amount_cents'] as num).toInt(),
            transactionCostCents: (row['transaction_cost_cents'] as num?)?.toInt(),
            counterpartyLabel: row['counterparty_label'] as String?,
            counterpartyPhone: row['counterparty_phone'] as String?,
            paybillAccountNumber: row['paybill_account_number'] as String?,
            classificationName: row['classification_name'] as String,
            groupDisplayName: row['group_display_name'] as String,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(row['transaction_occurred_at'] as int),
          ),
        )
        .toList();
  }

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Plain decimal (no `Ksh` prefix/thousands separators, unlike
  /// `formatKsh`) — deliberately spreadsheet-friendly so Amount/Cost
  /// columns import as numbers a PM can sum/pivot directly, not text.
  static String _decimal(int cents) {
    final isNegative = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}$whole.$frac';
  }

  static String _dateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Formats [rows] as CSV text — RFC 4180-style quoting, CRLF line
  /// endings, header row first.
  static String toCsv(List<ExportTransactionRow> rows) {
    final buffer = StringBuffer();
    buffer.write(csvHeader.join(','));
    buffer.write('\r\n');
    for (final r in rows) {
      final fields = [
        _dateTime(r.occurredAt),
        r.sourceType,
        r.groupDisplayName,
        r.classificationName,
        r.counterpartyLabel ?? '',
        r.counterpartyPhone ?? '',
        r.paybillAccountNumber ?? '',
        _decimal(r.amountCents),
        r.transactionCostCents != null ? _decimal(r.transactionCostCents!) : '',
        r.displayCode,
      ].map(_csvField);
      buffer.write(fields.join(','));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }
}
