@Tags(['autoread'])
library;

// 0.2.2 item 2, slice U6: the auto-read side's restore wording for the Backup result sheet (from
// hard_rule_copy keys only, counts only). Flag off = nothing; n = 0 = nothing; details-off drop =
// title, count body, Open Settings; Auto-record people back on Ask first = the count line; install /
// uninstall set the lib/ui holder; the installed messages drawn in the real result sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/restore_rule_messages.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_rules.dart';
import 'package:mmogo/data/backup/restore_types.dart';
import 'package:mmogo/ui/screens/backup/restore_result_sheet.dart';
import 'package:mmogo/ui/screens/backup/restore_rules_note.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

void main() {
  tearDown(() {
    debugAutoRecordUiOverride = null;
    uninstallRestoreRuleMessages();
  });

  test('flag off: the details-off note still shows when rules were dropped (B1 is not behind the flag)', () {
    debugAutoRecordUiOverride = false;
    final n = restoreRuleNotes(const RulesRestoreOutcome(droppedForPrivacy: 3)).single;
    expect([n.title, n.body, n.settingsButton], [kHardRestoreOffTitle, hardRestoreOffBody(3), kHardOpenSettings]);
  });

  test('flag off: no Auto-record review line', () {
    debugAutoRecordUiOverride = false;
    expect(restoreRuleNotes(const RulesRestoreOutcome(autoRecordAsAskFirst: 2)), isEmpty);
    expect(restoreRuleNotes(const RulesRestoreOutcome(droppedForPrivacy: 1, autoRecordAsAskFirst: 2)).single.title,
        kHardRestoreOffTitle);
  });

  group('flag on', () {
    setUp(() => debugAutoRecordUiOverride = true);

    test('n = 0 on both counts: nothing (other counts do not speak)', () {
      expect(restoreRuleNotes(RulesRestoreOutcome.none), isEmpty);
      expect(restoreRuleNotes(const RulesRestoreOutcome(added: 5, keptPhone: 2, paybillAsAskFirst: 1)), isEmpty);
    });

    test('details OFF drop: title, counts-only body, Open Settings', () {
      final n = restoreRuleNotes(const RulesRestoreOutcome(droppedForPrivacy: 3)).single;
      expect(n.title, kHardRestoreOffTitle);
      expect(n.body, hardRestoreOffBody(3));
      expect(n.settingsButton, kHardOpenSettings);
    });

    test('Auto-record people back on Ask first: the review count line, no button', () {
      final n = restoreRuleNotes(const RulesRestoreOutcome(added: 4, autoRecordAsAskFirst: 2)).single;
      expect(n.title, isNull);
      expect(n.body, hardRestoreToast(2));
      expect(n.settingsButton, isNull);
    });

    test('install / uninstall set and clear the lib/ui holder', () {
      expect(RestoreRulesNotes.builder, isNull);
      installRestoreRuleMessages();
      expect(RestoreRulesNotes.notesFor(const RulesRestoreOutcome(autoRecordAsAskFirst: 1)).single.body, hardRestoreToast(1));
      uninstallRestoreRuleMessages();
      expect(RestoreRulesNotes.builder, isNull);
    });

    testWidgets('installed: the real result sheet says "Backup restored. 3 people need a review."', (t) async {
      installRestoreRuleMessages();
      final r = RestoreResult(
        mode: RestoreMode.replace,
        tally: const RestoreTally(
          classifications: TableCounts(added: 1),
          transactions: TableCounts(added: 3),
          counterpartyMap: TableCounts(added: 2),
        ),
        settings: const SettingsApplyResult(ok: true),
        rules: const RulesRestoreOutcome(added: 5, autoRecordAsAskFirst: 3),
      );
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                key: const Key('open'),
                onPressed: () => showRestoreResultSheet(c, r, kind: RestoreSheetKind.replaced),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
      expect(find.text(hardRestoreToast(3)), findsOneWidget);
      expect(find.text(kHardOpenSettings), findsNothing);
    });
  });
}
