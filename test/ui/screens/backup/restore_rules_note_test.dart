// 0.2.2 item 2, slice U6: the restore result sheet's rules note, through the plain holder in lib/ui
// (RestoreRulesNotes). No holder = today's sheet exactly; a note draws its title, body and an
// "Open Settings" button that opens Settings with the "Record receiver details" switch outlined; a
// failing builder draws nothing. The text here is test text: the real wording comes from the
// auto-read side (restore_rule_messages_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_rules.dart';
import 'package:mmogo/data/backup/restore_types.dart';
import 'package:mmogo/ui/screens/backup/restore_result_sheet.dart';
import 'package:mmogo/ui/screens/backup/restore_rules_note.dart';
import 'package:mmogo/ui/screens/settings/settings_targets.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';

RestoreResult result({RulesRestoreOutcome? rules}) => RestoreResult(
      mode: RestoreMode.merge,
      tally: const RestoreTally(
        classifications: TableCounts(added: 1),
        transactions: TableCounts(added: 3),
        counterpartyMap: TableCounts(added: 2),
      ),
      settings: const SettingsApplyResult(ok: true),
      rules: rules,
    );

final pushed = <String>[];

Future<void> openSheet(WidgetTester t, RestoreResult r, {double scale = 1, String mode = 'light'}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      onGenerateRoute: (s) {
        pushed.add(s.name ?? '');
        return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('settings page')));
      },
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () => showRestoreResultSheet(c, r, kind: RestoreSheetKind.merged),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Iterable<String> sheetTexts(WidgetTester t) =>
    t.widgetList<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Text))).map((w) => w.data ?? '');

const offNote = RestoreRulesNote(title: 'T-off', body: 'B-off 3', settingsButton: 'Btn-settings');
const reviewNote = RestoreRulesNote(body: 'B-review 2');

void main() {
  setUp(pushed.clear);
  tearDown(() => RestoreRulesNotes.builder = null);

  test('notesFor: no builder, no rules part, or a failing builder = nothing', () {
    const o = RulesRestoreOutcome(droppedForPrivacy: 3);
    expect(RestoreRulesNotes.notesFor(o), isEmpty);
    RestoreRulesNotes.builder = (_) => const [offNote];
    expect(RestoreRulesNotes.notesFor(null), isEmpty);
    expect(RestoreRulesNotes.notesFor(o), [offNote]);
    RestoreRulesNotes.builder = (_) => throw StateError('boom');
    expect(RestoreRulesNotes.notesFor(o), isEmpty);
  });

  testWidgets('holder null: today\'s sheet exactly, even with rule counts in the result', (t) async {
    await openSheet(t, result());
    final today = sheetTexts(t).toList();
    Navigator.of(t.element(find.byKey(const Key('restoreResultSheet')))).pop();
    await t.pumpAndSettle();
    await openSheet(t, result(rules: const RulesRestoreOutcome(droppedForPrivacy: 3, autoRecordAsAskFirst: 2)));
    expect(sheetTexts(t).toList(), today);
    expect(find.byKey(const Key('restoreRulesNote0')), findsNothing);
  });

  testWidgets('builder returns nothing (n = 0): nothing drawn', (t) async {
    RestoreRulesNotes.builder = (_) => const [];
    await openSheet(t, result(rules: RulesRestoreOutcome.none));
    expect(find.byKey(const Key('restoreRulesNote0')), findsNothing);
  });

  testWidgets('notes drawn under the counts; Open Settings opens Settings at Record receiver details', (t) async {
    final h = t.ensureSemantics();
    RestoreRulesNotes.builder = (o) => [
          if (o.droppedForPrivacy > 0) offNote,
          if (o.autoRecordAsAskFirst > 0) reviewNote,
        ];
    await openSheet(t, result(rules: const RulesRestoreOutcome(droppedForPrivacy: 3, autoRecordAsAskFirst: 2)));
    expect(find.text('T-off'), findsOneWidget);
    expect(find.text('B-off 3'), findsOneWidget);
    expect(find.text('B-review 2'), findsOneWidget);
    expect(find.byKey(const Key('restoreRulesNote1')), findsOneWidget);
    final btn = find.byKey(const Key('restoreRulesOpenSettings'));
    expect(btn, findsOneWidget);
    expect(t.getSize(btn).height, greaterThanOrEqualTo(44));
    await t.tap(btn);
    await t.pumpAndSettle();
    expect(pushed, [Routes.settings]);
    expect(HighlightRequest.take(), kSettingsTargetCaptureReceiver);
    h.dispose();
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('200% text, $mode: no overflow', (t) async {
      RestoreRulesNotes.builder = (_) => const [offNote, reviewNote];
      await openSheet(t, result(rules: const RulesRestoreOutcome(droppedForPrivacy: 3)), scale: 2, mode: mode);
      expect(t.takeException(), isNull);
      expect(find.text('B-off 3'), findsOneWidget);
    });
  }
}
