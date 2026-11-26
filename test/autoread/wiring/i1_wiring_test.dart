// 0.2.2 item 2, slice I1: the real Auto-record objects RulesWiring installs. ONE pause port shared by every
// pause control (Settings row, Remembered card, banner), the one pill (RuleChangePill) as the level page's
// AND the offers list's notice, the offers' Change ceiling wired, and the restore result's rule notes
// installed with the backup seams whatever the Auto-record flag says. Mock preferences; invented data only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_pause_card.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/restore_rule_messages.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill.dart';
import 'package:mmogo/autoread/ui/settings/suggest_settings_section.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/data/backup/restore_rules.dart' show RulesRestoreOutcome;
import 'package:mmogo/ui/screens/backup/restore_rules_note.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RulesWiring.database = () async => throw StateError('no database in this test');
  });
  tearDown(() {
    RulesWiring.uninstall();
    debugAutoRecordUiOverride = null;
  });

  group('LevelsDeps.instance gets the real objects', () {
    test('the pause port is the ONE PrefsHardRulePausePort, the notice is the pill', () {
      RulesWiring.install();
      final d = LevelsDeps.instance!;
      expect(d.pause, isA<PrefsHardRulePausePort>());
      expect(d.pause, same(RulesWiring.pausePort));
      expect(d.notice, isA<RuleChangePill>());
      expect(d.bulk.store, same(AutoReadRuntime.ruleStore));
    });

    test('a reinstall keeps the same pause port (every control shares one change signal)', () {
      RulesWiring.install();
      final first = LevelsDeps.instance!.pause;
      RulesWiring.uninstall();
      RulesWiring.install();
      expect(LevelsDeps.instance!.pause, same(first));
    });

    test('the offers list shows the pill and offers Change ceiling', () {
      RulesWiring.install();
      final c = RulesWiring.suggestions!;
      expect(c.notice, isA<RuleChangePill>());
      expect(c.onChangeCeiling, isNotNull);
    });

    test('the pause port writes the real key and reads it back (survives a restart of the objects)', () async {
      RulesWiring.install();
      expect(await LevelsDeps.instance!.pause!.isPaused(), isFalse);
      expect(await LevelsDeps.instance!.pause!.setPaused(true), isTrue);
      RulesWiring.uninstall();
      RulesWiring.install();
      expect(await LevelsDeps.instance!.pause!.isPaused(), isTrue);
      expect((await SharedPreferences.getInstance()).getBool('autoread_hard_paused'), isTrue);
    });
  });

  group('restore result notes (U6) go with the backup seams', () {
    const dropped = RulesRestoreOutcome(droppedForPrivacy: 2);

    test('installBackupRules installs them, flag OFF too (unconditional)', () {
      debugAutoRecordUiOverride = false;
      expect(RestoreRulesNotes.builder, isNull);
      RulesWiring.install();
      RulesWiring.installBackupRules();
      expect(RestoreRulesNotes.builder, isNotNull);
      expect(RestoreRulesNotes.notesFor(dropped), hasLength(1));
    });

    test('uninstall removes them with the seams', () {
      RulesWiring.install();
      RulesWiring.installBackupRules();
      RulesWiring.uninstall();
      expect(RestoreRulesNotes.builder, isNull);
    });

    test('the installed builder is restore_rule_messages.dart\'s', () {
      RulesWiring.installBackupRules();
      expect(RestoreRulesNotes.builder, same(restoreRuleNotes));
    });
  });

  group('the Settings row and the page card share the one port', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('flip in Settings: the card follows; flip on the card: the Settings row follows', (t) async {
      RulesWiring.install();
      final d = LevelsDeps.instance!;
      // Item 2 redesign U-CTRL (B-6): the page row is hidden while nobody is on Auto-record, so one is.
      // Real store over mock prefs: written outside the fake clock (it may wait on real timers).
      final saved = await t.runAsync(() => d.store.setLevel(ReceiverType.sendMoney, '0722000555',
          name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, at: DateTime.utc(2026, 11, 26)));
      expect(saved, isTrue);
      t.view.physicalSize = const Size(400, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          home: Scaffold(
            body: ListView(children: [
              const SuggestSettingsSection(),
              HardRulePauseCard(port: d.pause!, bulk: d.bulk),
            ]),
          ),
        ),
      ));
      await t.pumpAndSettle();
      bool sw(String k) => t.widget<Switch>(find.byKey(Key(k))).value;
      expect(find.byKey(const Key('hardPauseSettingsRow')), findsOneWidget);
      expect(sw('hardPauseSettingsSwitch'), isFalse);
      expect(sw('hardPauseSwitch'), isFalse);

      await t.tap(find.byKey(const Key('hardPauseSettingsSwitch')));
      await t.pumpAndSettle();
      expect(sw('hardPauseSettingsSwitch'), isTrue);
      expect(sw('hardPauseSwitch'), isTrue);

      await t.tap(find.byKey(const Key('hardPauseSwitch')));
      await t.pumpAndSettle();
      expect(sw('hardPauseSwitch'), isFalse);
      expect(sw('hardPauseSettingsSwitch'), isFalse);
      await t.pump(const Duration(seconds: 10)); // let the toasts go
      await t.pumpAndSettle();
    });

    testWidgets('flag off: no Settings pause row with the real wiring', (t) async {
      debugAutoRecordUiOverride = false;
      RulesWiring.install();
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SuggestSettingsSection()))),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hardPauseSettingsRow')), findsNothing);
    });
  });

  test('the offers list writes to the one rule store the level page uses', () {
    RulesWiring.install();
    expect(RulesWiring.suggestions!.store, same(LevelsDeps.instance!.store));
  });
}
