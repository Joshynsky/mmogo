/// §DATA.BACKUP.LINKS — what a backup does with a linked Cash entry's link (0.2.1).
///
/// PURE (no imports): used by the export repair (`BackupRepair`) and the restore
/// validator (`BackupValidator`) so both apply the SAME rule.
///
/// A transaction row in file shape may carry `parent_id` (the file-local `id` of the
/// withdrawal it is linked to, or null) and `cash_only_decided` (0 or 1). The rule:
///  - a link is kept only when the row is a CASH row, its parent is an AGENT_WITHDRAWAL
///    row of the same file, and the entries of that parent (in file order) still add up to
///    at most the parent's amount;
///  - any other link is DROPPED (set to null): the Cash entry stays as plain Cash and is
///    never refused for it;
///  - `cash_only_decided` = 1 on a row that is not a withdrawal is reset to 0.
///
/// Returns how many values were changed. The maps are edited in place (they are copies).
int resolveBackupLinks(List<Map<String, Object?>> rows) {
  final byId = <int, Map<String, Object?>>{
    for (final r in rows)
      if (r['id'] is int) r['id']! as int: r,
  };
  final taken = <int, int>{};
  var changed = 0;
  for (final r in rows) {
    final pid = r['parent_id'];
    if (pid != null) {
      final parent = pid is int ? byId[pid] : null;
      final amount = r['amount_cents'];
      final left = parent == null || parent['amount_cents'] is! int || amount is! int
          ? -1
          : (parent['amount_cents']! as int) - (taken[pid as int] ?? 0);
      final ok = r['source_type'] == 'CASH' &&
          parent != null &&
          parent['source_type'] == 'AGENT_WITHDRAWAL' &&
          amount is int &&
          amount <= left;
      if (ok) {
        taken[pid as int] = (taken[pid] ?? 0) + amount;
      } else {
        r['parent_id'] = null;
        changed++;
      }
    }
    if (r['cash_only_decided'] == 1 && r['source_type'] != 'AGENT_WITHDRAWAL') {
      r['cash_only_decided'] = 0;
      changed++;
    }
  }
  return changed;
}
