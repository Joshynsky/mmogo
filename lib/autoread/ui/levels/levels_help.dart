/// §AUTOREAD.LEVELS.HELP: the words of the page's ONE "?" while the second tab
/// shows: what the levels are, then the rules per type under a heading each
/// (the airtime rules moved here from under the two switches). The page draws
/// the sheet; this file only builds the text.
library;

import '../../../domain/format/source_types.dart' show sourceTypeName;
import '../../../ui/screens/remembered/remembered_extra_tab.dart';
import '../auto_record_copy.dart';
import 'levels_copy.dart';

RememberedExtraHelp levelsHelp() => RememberedExtraHelp(kLevelsHelpTitle, _paragraphs);

// The Airtime heading is the one type name from source_types.dart.
final List<String> _paragraphs = [
  kLevelsHelpLevels,
  kLevelsHelpHeadSend,
  kLevelsHelpReceiverRule,
  kLevelsHelpHeadPaybill,
  kLevelsHelpReceiverRule,
  kLevelsHelpHeadBuyGoods,
  kLevelsHelpReceiverRule,
  kLevelsHelpHeadPochi,
  kLevelsHelpPochiRule,
  kLevelsHelpHeadWithdrawals,
  kLevelsHelpWithdrawalsRule,
  sourceTypeName('AIRTIME'),
  kLevelsHelpAirtimeIntro,
  kLevelsHelpAirtimeTap,
  kAutoRecordExplainUndo,
  kAutoRecordExplainLater,
  kLevelsHelpPrivacy,
];
