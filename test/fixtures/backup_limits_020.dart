// A frozen copy of what the 0.2.0 backup reader allowed, for the "an older app refuses a
// newer file" pin. 0.2.0 shipped kBackupSchemaVersion = 5 and kBackupFormatVersion = 1, and its
// validator ran: format_version > 1 -> "newer"; schema_version > 5 -> "newer"; nothing is
// written before that check. NEVER edit these numbers: they describe an app already released.
const int kFixture020MaxSchema = 5;
const int kFixture020FormatVersion = 1;

/// The envelope check of the 0.2.0 validator (the part that decides "newer"), on a decoded file.
bool refusedAsNewerBy020(Map<String, Object?> envelope) {
  final format = envelope['format_version'];
  final schema = envelope['schema_version'];
  if (format is! int || schema is! int) return false;
  return format > kFixture020FormatVersion || schema > kFixture020MaxSchema;
}
