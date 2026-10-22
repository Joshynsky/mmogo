/// The Dart entry of "Parse from the notification" (stage 2, Wave C).
///
/// Kotlin's `ParseActionReceiver` starts a short-lived HEADLESS FlutterEngine with only
/// shared_preferences registered and runs [parseEntry] with the held id. This file runs the REAL
/// parser (the same [AutoReadService] the app uses) and talks to Kotlin over a channel that only
/// exists in that engine ([kBackgroundChannel]).
///
/// Sequence (the service enforces it): peekHeld -> parse -> write the waiting item -> READ IT BACK
/// -> ackHeld. Kotlin refuses the ack when the generation moved (Off, Delete data) or Parse is no
/// longer allowed; this side then removes the item it wrote. A failure at any step leaves the held
/// message held; Kotlin keeps the notification, so the body tap still parses in the app.
///
/// The headless engine has NO database plugin, so the saved-transactions check is skipped here (the
/// in-app Categorize save already treats an already-recorded code as a no-op). Only parsed fields are
/// written, never the text. The message body is never logged, printed or put in an error; only the
/// outcome code and a count of waiting items go back to Kotlin.
///
/// Autoread flavor only. Kotlin starts `parseFromNotificationEntry` in lib/main.dart BY NAME (the
/// entry point must live in the program's main library); that function calls [parseEntry] only when
/// `kAutoReadCompiled` is true, so the standard build tree-shakes this whole folder.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bridge/autoread_bridge.dart';
import '../bridge/method_channel_autoread_bridge.dart';
import '../data/pending_items_store.dart';
import '../model/waiting_item.dart' show isValidHeldId;
import '../service/autoread_service.dart';

/// The headless channel. Kotlin mirror: ParsePolicy.BG_CHANNEL (a test pins them).
const String kBackgroundChannel = 'app.mmogo/autoread_bg';

/// The codes sent in `done`. Kotlin mirror: ParsePolicy.Outcome (a test pins them).
const String kBgParsed = 'parsed';
const String kBgDuplicate = 'duplicate';
const String kBgUnreadable = 'unreadable';
const String kBgGone = 'gone';
const String kBgNotSaved = 'not_saved';
const String kBgFull = 'full';
const String kBgStale = 'stale';
const String kBgError = 'error';

/// Every code this side can send ('watchdog' is Kotlin's own).
const List<String> kBackgroundOutcomeCodes = [
  kBgParsed,
  kBgDuplicate,
  kBgUnreadable,
  kBgGone,
  kBgNotSaved,
  kBgFull,
  kBgStale,
  kBgError,
];

/// What a background parse ended as: a code and how many parsed items are now waiting (a number).
class BackgroundResult {
  const BackgroundResult(this.code, this.waiting);
  final String code;
  final int waiting;

  @override
  String toString() => 'BackgroundResult($code, $waiting)';
}

/// There is no database in the headless engine: nothing is "already saved" here.
class NoSavedCodes implements CodeLookup {
  const NoSavedCodes();
  @override
  Future<bool> contains(String displayCode) async => false;
}

/// The channel to Kotlin's runner. It answers for ONE id (the one it started with) and reports whether
/// Kotlin refused the ack.
class BackgroundBridge extends MethodChannelAutoReadBridge {
  BackgroundBridge({required MethodChannel channel, required super.generation})
      : _ch = channel,
        super(channel: channel);

  final MethodChannel _ch;

  /// True when Kotlin did not ack (the generation moved or Parse is no longer allowed).
  bool stale = false;

  @override
  Future<void> ackHeld(String id, {required int generation}) async {
    if (!isValidHeldId(id)) return;
    final r = await _ch.invokeMethod<Object?>('ackHeld', <String, Object?>{'id': id, 'generation': generation});
    if (r != 'acked') stale = true;
  }
}

/// The parse itself, with its collaborators passed in so a test can run it with fakes.
Future<BackgroundResult> runBackgroundParse({
  required String id,
  required AutoReadBridge bridge,
  required PendingItemsStore store,
  bool Function()? wasStale,
  SmsParseFn? parser,
}) async {
  if (!isValidHeldId(id)) return const BackgroundResult(kBgGone, 0);
  final service = AutoReadService(
    bridge: bridge,
    store: store,
    savedCodes: const NoSavedCodes(),
    now: DateTime.now,
    parser: parser,
  );
  final outcome = await service.parse(id);
  if (wasStale?.call() ?? false) {
    // Kotlin did not ack: the generation moved (Off or Delete data) or Parse was turned off while we
    // worked. Discard what this run wrote; the message stays held.
    try {
      await store.remove(id);
    } catch (_) {}
    return const BackgroundResult(kBgStale, 0);
  }
  var waiting = 0;
  try {
    waiting = await store.count();
  } catch (_) {}
  switch (outcome) {
    case ParseOutcome.parsed:
      return BackgroundResult(kBgParsed, waiting);
    case ParseOutcome.duplicate:
      return BackgroundResult(kBgDuplicate, waiting);
    case ParseOutcome.gone:
      return BackgroundResult(kBgGone, waiting);
    case ParseOutcome.couldNotRead:
      return BackgroundResult(
        switch (service.lastFailure) {
          ParseFailure.notRecognised || ParseFailure.tooLong => kBgUnreadable,
          ParseFailure.queueFull => kBgFull,
          ParseFailure.notSaved => kBgNotSaved,
          null => kBgError,
        },
        waiting,
      );
  }
}

/// Sends `done` to Kotlin at most once per run (a late error after a normal end sends nothing).
class BackgroundReporter {
  BackgroundReporter(this._ch);
  final MethodChannel _ch;
  bool _sent = false;

  bool get sent => _sent;

  Future<void> done(String code, int waiting) async {
    if (_sent) return;
    _sent = true;
    try {
      await _ch.invokeMethod<void>('done', <String, Object?>{'outcome': code, 'waiting': waiting});
    } catch (_) {}
  }
}

/// The whole entry, testable: [args] is `[heldId]`.
Future<void> runBackgroundEntry(List<String> args, {MethodChannel? channel, BackgroundReporter? reporter}) async {
  final ch = channel ?? const MethodChannel(kBackgroundChannel);
  final out = reporter ?? BackgroundReporter(ch);
  final id = args.isEmpty ? '' : args.first;
  if (!isValidHeldId(id)) return out.done(kBgGone, 0);
  final store = SharedPrefsPendingItemsStore();
  final bridge = BackgroundBridge(channel: ch, generation: store.readGeneration);
  try {
    final r = await runBackgroundParse(id: id, bridge: bridge, store: store, wasStale: () => bridge.stale);
    await out.done(r.code, r.waiting);
  } catch (_) {
    // Only the fact of a failure goes back; never the error text (it could carry the message).
    await out.done(kBgError, 0);
  }
}

/// Called by `parseFromNotificationEntry` in lib/main.dart (the function Kotlin's `ParseRunner` starts;
/// ParsePolicy.ENTRY_LIBRARY / ENTRY_FUNCTION).
void parseEntry(List<String> args) {
  final out = BackgroundReporter(const MethodChannel(kBackgroundChannel));
  PlatformDispatcher.instance.onError = (Object e, StackTrace s) {
    unawaited(out.done(kBgError, 0));
    return true;
  };
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await runBackgroundEntry(args, reporter: out);
  }, (Object e, StackTrace s) {
    unawaited(out.done(kBgError, 0));
  });
}