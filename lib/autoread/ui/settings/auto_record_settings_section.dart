/// §AUTOREAD.SETTINGS.AUTO_RECORD: the Auto-record section of Settings (item 3 slice E, auto-read build only):
/// People (the Remembered page, with its count), Pause all Auto-record, Offer Ask first, Offer after N in a row.
/// The two airtime switches stay on the People page (they are one controller shared with the To do page and
/// the page's second tab; the People row's line says how many are on). Composition only: the rows are drawn by
/// [SuggestSettingsSection], which keeps its ports and the pause switch in one place.
library;

import 'package:flutter/material.dart';

import '../../../ui/copy/settings_copy.dart';
import '../levels/hard_rule_ports.dart';
import '../levels/levels_deps.dart' show SuggestSettingsPort;
import 'suggest_settings_section.dart';

class AutoRecordSettingsSection extends StatelessWidget {
  /// [people] is the People row (null = no row, e.g. when the app has no airtime controller);
  /// the ports are test seams (null = the app's own).
  const AutoRecordSettingsSection({super.key, this.people, this.port, this.pause, this.bulk});

  final Widget? people;
  final SuggestSettingsPort? port;
  final HardRulePausePort? pause;
  final RuleBulkOps? bulk;

  @override
  Widget build(BuildContext context) {
    return SuggestSettingsSection(title: kSettingsAutoRecordGroup, leading: people, port: port, pause: pause, bulk: bulk);
  }
}
