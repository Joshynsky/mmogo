/// Formats a byte count for Profile's "Storage used (est.)" row (T17),
/// matching the prototype's own rule: under 1 KB shows
/// raw bytes, otherwise one-decimal KB — extended with one-decimal MB at
/// 1024 KB and above, since a real SQLite file (unlike the prototype's
/// localStorage JSON) routinely passes 1 MB. `null` (size unknown) renders
/// as an em dash, the same placeholder the prototype uses before load.
String formatByteSize(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes bytes';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
