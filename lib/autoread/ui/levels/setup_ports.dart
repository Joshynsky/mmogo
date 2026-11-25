/// §AUTOREAD.LEVELS.SETUP_PORTS: the seams of the 0.2.2 item 2 redesign that the Set up sheet and the person
/// sheet share, so no two wave-1 slices edit the same file: the Set up list ([SetupRecipientsSource], real one
/// by slice B-SRC) and the category chips picker ([PickCategories], real one by slice U-PICK). Interfaces only;
/// I2 installs the real ones into LevelsDeps. Null in LevelsDeps = the feature is absent.
library;

import 'package:flutter/widgets.dart';

import '../../rules/rule_model.dart';
import '../category_choices.dart';

// ---------------------------------------------------------------- the Set up list

/// One recipient the Set up sheet lists (mock setup-*). Send Money, Pochi, Buy Goods and Paybill only.
class SetupRecipient {
  const SetupRecipient({
    required this.type,
    required this.key,
    required this.displayName,
    this.maskedNumber,
    required this.paymentCount,
    this.level,
  });

  final ReceiverType type;

  /// The normalised key (`receiverKey`), the same key the rule store uses.
  final String key;

  /// The name to show.
  final String displayName;

  /// Already masked by the source (0722***555); null when the recipient has no number to show. The full
  /// number never reaches the sheet.
  final String? maskedNumber;

  /// Non-deleted payments to this recipient ("{k} payments").
  final int paymentCount;

  /// The stored level; null = no rule yet (a new person, or one removed by Forget all).
  final RuleLevel? level;

  @override
  bool operator ==(Object other) =>
      other is SetupRecipient &&
      other.type == type &&
      other.key == key &&
      other.displayName == displayName &&
      other.maskedNumber == maskedNumber &&
      other.paymentCount == paymentCount &&
      other.level == level;

  @override
  int get hashCode => Object.hash(type, key, displayName, maskedNumber, paymentCount, level);

  @override
  String toString() => 'SetupRecipient(${type.code}, $key, $displayName, $maskedNumber, $paymentCount, ${level?.name})';
}

/// Where the Set up sheet's list comes from (the ledger; slice B-SRC).
abstract class SetupRecipientsSource {
  /// Every recipient, or only those of [type] when given, in the order the sheet shows them (the source
  /// decides). Empty while "Record receiver details" is OFF.
  Future<List<SetupRecipient>> list({ReceiverType? type});
}

// ---------------------------------------------------------------- the category chips picker

/// [one]: a single category (Ask first, Auto-record). [upTo2]: up to [kMaxChosenCategories] (Suggest from:
/// Categories I choose).
enum CategoryPickMode { one, upTo2 }

/// Opens the category chips picker (mock pick-one, pick-multi) over [context].
/// [choices]: the categories to offer for this person's type (LevelsDeps.choicesFor). [initial]: the ids chosen
/// when it opens (placed first). [usedBefore]: ids this person was paid under before (marked with a dot and a
/// text label). Ids are `int.parse(CategoryChoice.id)`; a choice whose id is not a whole number is not offered
/// (as category_pick_sheet.dart does).
/// Returns the chosen ids in the order chosen (at most 1 for [CategoryPickMode.one], at most
/// [kMaxChosenCategories] for [CategoryPickMode.upTo2]), or null when the picker was closed without a choice.
typedef PickCategories = Future<List<int>?> Function(
  BuildContext context, {
  required CategoryPickMode mode,
  required List<CategoryChoice> choices,
  required List<int> initial,
  required Set<int> usedBefore,
});
