import 'name_only_fields.dart';
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

  /// 0.1.2 S8a (NO1): a `sent to <NAME>` message with no phone or account.
  const factory ParseResult.needsType(NameOnlyFields fields) = ParseNeedsType;
}

/// The paste is longer than `kSmsMaxChars`. A [ParseError] subtype so every
/// existing `case ParseError` keeps working; the UI tells it apart with
/// `result is ParseTooLong`. The wording is a placeholder until S8c WD9.
class ParseTooLong extends ParseError {
  const ParseTooLong() : super(kSmsTooLongReason);
}

const String kSmsTooLongReason =
    'This message is too long to be one M-Pesa message. Paste just the one '
    'message you want to add.';

/// A name-only message: carries the fields but NO source type, so it is never
/// saved by itself. The Add flow (S8c) asks the user for the type; until then
/// the existing paste screen shows the not-recognised text for it.
class ParseNeedsType extends ParseResult {
  final NameOnlyFields fields;
  const ParseNeedsType(this.fields);

  @override
  String toString() => 'ParseNeedsType($fields)';

  @override
  bool operator ==(Object other) =>
      other is ParseNeedsType && other.fields == fields;

  @override
  int get hashCode => fields.hashCode;
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
