import '../../../domain/parsing/name_only_resolver.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';

/// §ADD.NAME_ONLY_STATE — 0.1.2 S8c-2 (NO4). What the Add screen knows about a
/// name-only message while the form is open: plain data and one rule, no
/// widgets, no storage, so it is tested without pumping a page.
///
/// "No type yet" is held as [pending] (a flag), not as a nullable type: the
/// screen keeps its `_type` string (Send Money while pending) so no other rule
/// has to learn about a missing type; every place that must treat the form as
/// undecided asks [pending].
class NameOnlyState {
  /// The form came from a name-only message (and has not been started over).
  bool active = false;

  /// The type is not chosen yet (the ask was closed, or has not opened yet).
  bool pending = false;

  /// The name as printed in the SMS (shown in the ask by design).
  String name = '';

  /// `deriveRecipientNameKey` of [name], taken when the message was parsed. The
  /// remembered answer is stored under THIS key, never the live Name field.
  String key = '';

  /// `'memory'` (a remembered answer filled the type) or `'chosen'` (the user
  /// chose in the ask); null while pending.
  String? how;

  /// The "Remember this choice" tick. Lives here so it survives a reopen.
  bool tick = true;

  /// What memory held for [key] at parse time (a hit), or null.
  RecipientRule? remembered;

  void reset() {
    active = false;
    pending = false;
    name = '';
    key = '';
    how = null;
    tick = true;
    remembered = null;
  }

  void start({required String name, required String key}) {
    reset();
    active = true;
    pending = true;
    this.name = name;
    this.key = key;
  }

  /// True when the answer should be written to recipient memory, given the LIVE
  /// "Also record the receiver's details" switch at save time. Rule: a name-only
  /// form, a decided type, the switch ON, the tick ON, a usable key, and not an
  /// unchanged remembered answer (that writes nothing, not even a fresh time).
  bool shouldRemember({required bool captureOn, required SmsSourceType? type}) {
    if (!active || pending || key.isEmpty) return false;
    if (!captureOn || !tick) return false;
    if (type != SmsSourceType.sendMoney && type != SmsSourceType.pochi) return false;
    if (remembered != null && remembered!.type == type) return false;
    return true;
  }
}
