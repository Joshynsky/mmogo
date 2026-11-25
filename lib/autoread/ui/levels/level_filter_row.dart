/// §AUTOREAD.LEVELS.FILTER_ROW: the level filter row was REMOVED in 0.2.2 (PM D3: layout A's sections and
/// search replace it). Only [levelTagText] is left, because level_sheet.dart (slice U1's file) imports it
/// from here for the 0.2.1 two-level sheet. Move it next to the sheet and delete this file at merge.
library;

import '../../rules/rule_model.dart';
import 'levels_copy.dart';

/// The words of a level tag on the 0.2.1 sheet (two levels).
String levelTagText(RuleLevel l) => switch (l) {
      RuleLevel.askFirst => kLevelAskFirst,
      _ => kLevelSuggested,
    };
