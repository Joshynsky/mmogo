import 'parsed_sms_fields.dart';

// A parse outcome is either `ParseResult.Success(fields)` or
// `ParseResult.Error(reason)`, never persisted (there is no
// `failed_parse_attempts` table). Implemented here as a
// sealed Dart union so T6/T14's UI layer must handle both cases
// exhaustively (an unmatched paste is transient UI state only, an
// explicit error rather than a silent fallback — it is
// never written anywhere, including here: this type never touches
// storage).
sealed class ParseResult {
  const ParseResult();

  const factory ParseResult.success(ParsedSmsFields fields) = ParseSuccess;

  const factory ParseResult.error(String reason) = ParseError;
}

class ParseSuccess extends ParseResult {
  final ParsedSmsFields fields;
  const ParseSuccess(this.fields);

  @override
  String toString() => 'ParseSuccess($fields)';

  @override
  bool operator ==(Object other) =>
      other is ParseSuccess && other.fields == fields;

  @override
  int get hashCode => fields.hashCode;
}

class ParseError extends ParseResult {
  final String reason;
  const ParseError(this.reason);

  @override
  String toString() => 'ParseError($reason)';

  @override
  bool operator ==(Object other) =>
      other is ParseError && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}
