/// §AUTOREAD.SERVICE — turns one held message into a waiting item.
///
/// Order: validate id, claim, peek, cap length, parse (the app's existing
/// parser), put, READ BACK, and only then ack. A crash between the write and
/// the ack is harmless: the next parse sees the same item and answers
/// [ParseOutcome.duplicate]. The message body is never logged or printed; the
/// only values ever reported are outcome codes.
library;

import '../../domain/parsing/parse_result.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../domain/parsing/sms_parser.dart';
import '../bridge/autoread_bridge.dart';
import '../data/pending_items_store.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart' show ParseOutcome;

export '../model/waiting_repository.dart' show ParseOutcome;

/// Why the last [AutoReadService.parse] ended as [ParseOutcome.couldNotRead].
enum ParseFailure {
  /// The text is not a recognised M-Pesa confirmation (or needs a type).
  notRecognised,

  /// More than [kAutoReadMaxChars] characters.
  tooLong,

  /// The waiting list is full; the message stays held.
  queueFull,

  /// The write could not be read back; the message stays held.
  notSaved,
}

/// Longest held message the service will parse (more than this is refused).
const int kAutoReadMaxChars = 2000;

/// Is this M-Pesa code already a saved transaction? The app wires it to saved
/// transactions later.
abstract class CodeLookup {
  Future<bool> contains(String displayCode);
}

/// A parse function with the same shape as `SmsParser.parse`.
typedef SmsParseFn = ParseResult Function(String rawMessage);

class AutoReadService {
  AutoReadService({
    required AutoReadBridge bridge,
    required PendingItemsStore store,
    required CodeLookup savedCodes,
    required DateTime Function() now,
    SmsParseFn? parser,
  })  : _bridge = bridge,
        _store = store,
        _savedCodes = savedCodes,
        _now = now,
        _parser = parser ?? SmsParser.parse;

  final AutoReadBridge _bridge;
  final PendingItemsStore _store;
  final CodeLookup _savedCodes;
  // ignore: unused_field
  final DateTime Function() _now;
  final SmsParseFn _parser;

  ParseFailure? _lastFailure;

  /// The reason for the last [ParseOutcome.couldNotRead]; null after any other
  /// outcome.
  ParseFailure? get lastFailure => _lastFailure;

  Future<ParseOutcome> parse(String id) async {
    _lastFailure = null;
    if (!isValidHeldId(id)) return ParseOutcome.gone;
    if (!await _bridge.claim(id)) return ParseOutcome.gone;
    try {
      return await _parseClaimed(id);
    } finally {
      await _bridge.release(id);
    }
  }

  Future<ParseOutcome> _parseClaimed(String id) async {
    final held = await _bridge.peekHeld(id);
    if (held == null) return ParseOutcome.gone;

    if (held.body.length > kAutoReadMaxChars) {
      return _fail(ParseFailure.tooLong);
    }

    final result = _parser(held.body);
    final ParsedSmsFields? fields = switch (result) {
      ParseSuccess(:final fields) => fields,
      _ => null,
    };
    if (fields == null) return _fail(ParseFailure.notRecognised);

    final generation = await _bridge.readGeneration();

    if (await _savedCodes.contains(fields.code)) {
      await _bridge.ackHeld(id, generation: generation);
      return ParseOutcome.duplicate;
    }

    final item = WaitingItem(
      id: id,
      kind: WaitingKind.waitingCategory,
      heldAt: held.heldAt,
      parsed: fields,
    );

    switch (await _store.put(item, generation: generation)) {
      case StoreResult.stored:
      case StoreResult.storedFlagged:
        final stored = await _store.list();
        if (!stored.any((i) => i.id == id)) {
          // Not read back: keep the message held.
          return _fail(ParseFailure.notSaved);
        }
        await _bridge.ackHeld(id, generation: generation);
        return ParseOutcome.parsed;
      case StoreResult.duplicate:
        await _bridge.ackHeld(id, generation: generation);
        return ParseOutcome.duplicate;
      case StoreResult.full:
        return _fail(ParseFailure.queueFull);
      case StoreResult.staleGeneration:
        return ParseOutcome.gone;
    }
  }

  ParseOutcome _fail(ParseFailure why) {
    _lastFailure = why;
    return ParseOutcome.couldNotRead;
  }
}
