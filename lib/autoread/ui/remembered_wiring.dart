/// §AUTOREAD.REMEMBERED_WIRING: how the auto-read build plugs the airtime
/// switches into Settings and the Remembered page. Both take the ONE shared
/// switch controller, so the page, the Settings row and the trail
/// always agree. main.dart only calls these two functions.
library;

import '../../data/prefs/recipient_memory.dart' show RecipientMemory;
import '../../ui/screens/remembered/remembered_screen.dart';
import '../../ui/screens/settings/remembered_hook_row.dart';
import '../../ui/shell/routes.dart' show RememberedRouteArgs;
import '../logic/airtime_auto.dart' show AirtimeAutoController;
import 'auto_record_tab.dart' show autoRecordExtraTab;

/// The Settings row hook: how many of the two switches are on (0 to 2) and ONE
/// count of kept names (a count only, never the names). [memory] is a test seam.
RememberedRowHook rememberedRowHookFor(AirtimeAutoController c, {RecipientMemory? memory}) =>
    RememberedRowHook(
      changes: c,
      load: () async => RememberedRowInfo(
        autoOn: (c.on ? 1 : 0) + (c.onOther ? 1 : 0),
        names: (await (memory ?? RecipientMemory()).list()).length,
      ),
    );

/// The Remembered page with its second tab. [args] is the route argument
/// (a [RememberedRouteArgs] opens the second tab when asked).
RememberedScreen rememberedPageFor(AirtimeAutoController c, {Object? args, RecipientMemory? memory}) =>
    RememberedScreen(
      memory: memory,
      extraTab: autoRecordExtraTab(c),
      openExtraTab: args is RememberedRouteArgs && args.openAutoRecord,
    );
