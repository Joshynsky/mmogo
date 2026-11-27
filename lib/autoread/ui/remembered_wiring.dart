/// §AUTOREAD.REMEMBERED_WIRING: how the auto-read build plugs the airtime
/// switches into Settings and the Remembered page. Both take the ONE shared
/// switch controller, so the page, the Settings row and the trail
/// always agree. main.dart only calls these two functions.
library;

import '../../data/prefs/app_prefs.dart' show AppPrefs;
import '../../data/prefs/recipient_memory.dart' show RecipientMemory;
import '../../ui/screens/remembered/remembered_screen.dart';
import '../../ui/screens/settings/remembered_hook_row.dart';
import '../../ui/shell/routes.dart' show RememberedRouteArgs;
import '../logic/airtime_auto.dart' show AirtimeAutoController;
import '../rules/rule_cleanup.dart' show RuleCleanup;
import 'levels/hard_rule_ports.dart' show autoRecordUi;
import 'levels/hard_rule_slots.dart';
import 'levels/levels_deps.dart' show LevelsDeps;
import 'levels/levels_people_count.dart' show levelsPeopleCount;
import 'levels/levels_tab.dart' show levelsExtraTab;

/// The Settings row hook: how many of the two switches are on (0 to 2) and ONE
/// count of kept names (a count only, never the names). [memory] is a test seam.
/// [levels] (null = [LevelsDeps.instance]) gives the count of people with rules; none = no people part.
RememberedRowHook rememberedRowHookFor(AirtimeAutoController c, {RecipientMemory? memory, LevelsDeps? levels}) =>
    RememberedRowHook(
      changes: c,
      load: () async {
        final d = levels ?? LevelsDeps.instance;
        int? people;
        if (d != null) {
          try {
            people = await levelsPeopleCount(d);
          } catch (_) {}
        }
        return RememberedRowInfo(
          autoOn: (c.on ? 1 : 0) + (c.onOther ? 1 : 0),
          names: (await (memory ?? RecipientMemory()).list()).length,
          people: people,
        );
      },
    );

/// The Remembered page with its second tab. [args] is the route argument
/// (a [RememberedRouteArgs] opens the second tab when asked).
/// [levels] null = the app's [LevelsDeps.instance]; when that is unset too, the
/// second tab shows the airtime switches only. [cleanup] (the app passes its own) makes Forget, Change to
/// Send Money and Forget all also remove the person's rule.
/// 0.2.2 (I1): while the Auto-record screens are on, the second tab gets its page controls
/// ([hardRuleSlotsFor]: pause card, paused banner, review line, reset footer) and reads "Record receiver
/// details" ([detailsOn], default the app's setting) for its details-OFF page. Flag off: neither, so the
/// tab is exactly the 0.2.1 one.
RememberedScreen rememberedPageFor(AirtimeAutoController c,
    {Object? args, RecipientMemory? memory, LevelsDeps? levels, RuleCleanup? cleanup, Future<bool> Function()? detailsOn}) {
  final deps = levels ?? LevelsDeps.instance;
  final hard = autoRecordUi;
  return RememberedScreen(
    memory: memory,
    extraTab: levelsExtraTab(c,
        deps: deps,
        cleanup: cleanup,
        detailsOn: hard ? (detailsOn ?? AppPrefs.readCaptureIdentityPreference) : null,
        slots: hardRuleSlotsFor(deps)),
    openExtraTab: args is RememberedRouteArgs && args.openAutoRecord,
  );
}
