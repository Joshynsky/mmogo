/// §AUTOREAD.PLAIN_NAME: the ONE name cleaner for every pill that names a person (0.2.2 item 2, I2c; sign-off
/// "Pill: no phone number"). Pure. Every word that holds a digit or a mask star is dropped, so a Set up name
/// that is the masked number ("0722***555"), a rule named by its key ("0722123555") or "Name 0722***555"
/// (levelWho) never shows a number. Used by the change pill's callers (level_sheet_open.dart,
/// suggestions_controller.dart) and the no-tap arrival message (hard_rule_arrival_toast.dart).
library;

// WORDING-MISSING -> W2 (moved here unchanged from hard_rule_arrival_toast.dart, I2c; shown only when no plain
// name is left: no name at all, or a name made only of digits / a masked number)
const String _kTodoPersonName = '[PM to write: name when the person is not known]';

final RegExp _numberish = RegExp(r'[0-9*]');
final RegExp _spaces = RegExp(r'\s+');

/// The plain name in [raw], or null when nothing is left (blank, or only digits / mask stars).
String? plainPersonName(String? raw) {
  if (raw == null) return null;
  final name = raw.trim().split(_spaces).where((w) => w.isNotEmpty && !_numberish.hasMatch(w)).join(' ');
  return name.isEmpty ? null : name;
}

/// The name a pill shows: the plain name in [raw], else the W2 placeholder. Never a digit or a '*'.
String pillPersonName(String? raw) => plainPersonName(raw) ?? _kTodoPersonName;
