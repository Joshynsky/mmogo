@Tags(['autoread'])
library;

// 0.2.2 item 2 redesign, slice U-REST: the restore result sheet with the REAL signed restore lines
// installed (restore_rule_messages.dart over hard_rule_copy.dart). B-7 (second site): the details-off
// note's "Open Settings" opens Settings with HighlightRequest(kSettingsTargetCaptureReceiver) already
// set when the Settings route is built, so the "Record receiver details" switch is outlined. The
// signed lines render for 0 / 1 / 2 people (singular via the C1 helpers), at 200% text, light and
// dark, right-to-left, with 44 px targets and spoken labels.
import 'package:mmogo/ui/copy/backup_copy.dart' show restoreRulesNeedKeep;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/restore_rule_messages.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_rules.dart';
import 'package:mmogo/data/backup/restore_types.dart';
import 'package:mmogo/ui/screens/backup/restore_result_sheet.dart';
import 'package:mmogo/ui/screens/settings/settings_targets.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';

RestoreResult _result(RulesRestoreOutcome rules, {RestoreMode mode = RestoreMode.merge}) => RestoreResult(
  mode: mode,
  tally: const RestoreTally(
    classifications: TableCounts(added: 1),
    transactions: TableCounts(added: 3),
    counterpartyMap: TableCounts(added: 2),
  ),
  settings: const SettingsApplyResult(ok: true),
  rules: rules,
);

/// Route name pushed, and the highlight pending at the moment that route was built.
final _pushed = <(String, String?)>[];

Future<void> _openSheet(
  WidgetTester t,
  RestoreResult r, {
  RestoreSheetKind kind = RestoreSheetKind.merged,
  double scale = 1,
  String mode = 'light',
  TextDirection dir = TextDirection.ltr,
}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        builder: (c, w) => Directionality(
          textDirection: dir,
          child: MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!,
          ),
        ),
        onGenerateRoute: (s) => MaterialPageRoute<void>(
          builder: (_) {
            // Settings takes the request in its first build (settings_screen.dart:123); so does this stand-in.
            _pushed.add((s.name ?? '', HighlightRequest.take()));
            return const Scaffold(body: Text('settings page'));
          },
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () => showRestoreResultSheet(c, r, kind: kind),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

final _openSettings = find.byKey(const Key('restoreRulesOpenSettings'));

void main() {
  setUp(() {
    _pushed.clear();
    HighlightRequest.set(null);
    installRestoreRuleMessages();
  });
  tearDown(() {
    debugAutoRecordUiOverride = null;
    uninstallRestoreRuleMessages();
    HighlightRequest.set(null);
  });

  group('details off (rules left out)', () {
    testWidgets('B-7: Open Settings opens Settings with the Record receiver details switch requested', (t) async {
      await _openSheet(t, _result(const RulesRestoreOutcome(droppedForPrivacy: 2)));
      expect(_openSettings, findsOneWidget);
      expect(find.descendant(of: _openSettings, matching: find.text(kHardOpenSettings)), findsOneWidget);
      expect(HighlightRequest.take(), isNull, reason: 'nothing is requested before the tap');
      await t.tap(_openSettings);
      await t.pumpAndSettle();
      expect(_pushed, [(Routes.settings, kSettingsTargetCaptureReceiver)]);
      expect(find.text('settings page'), findsOneWidget);
      // Taken once: a later Settings visit is not lit.
      expect(HighlightRequest.take(), isNull);
    });

    testWidgets('B-7 also on the Replace result sheet', (t) async {
      await _openSheet(
        t,
        _result(const RulesRestoreOutcome(droppedForPrivacy: 1), mode: RestoreMode.replace),
        kind: RestoreSheetKind.replaced,
      );
      await t.tap(_openSettings);
      await t.pumpAndSettle();
      expect(_pushed, [(Routes.settings, kSettingsTargetCaptureReceiver)]);
    });

    for (final n in [1, 2]) {
      testWidgets('signed lines render for $n', (t) async {
        await _openSheet(t, _result(RulesRestoreOutcome(droppedForPrivacy: n)));
        expect(find.text(kHardRestoreOffTitle), findsOneWidget);
        expect(find.text(hardRestoreOffBody(n)), findsOneWidget);
        expect(hardRestoreOffBody(n), contains(n == 1 ? 'Settings for 1 person ' : 'Settings for 2 people '));
        expect(hardRestoreOffBody(n), isNot(contains('1 people')));
      });
    }

    testWidgets('0 left out: no note, no button', (t) async {
      await _openSheet(t, _result(RulesRestoreOutcome.none));
      expect(find.text(kHardRestoreOffTitle), findsNothing);
      expect(_openSettings, findsNothing);
      expect(find.byKey(const Key('restoreRulesNote0')), findsNothing);
    });
  });

  group('Auto-record people back on Ask first', () {
    for (final n in [1, 2]) {
      testWidgets('flag on: signed line renders for $n, no button', (t) async {
        debugAutoRecordUiOverride = true;
        await _openSheet(t, _result(RulesRestoreOutcome(added: 4, autoRecordAsAskFirst: n)));
        expect(find.text(restoreRulesNeedKeep(n)), findsOneWidget);
        expect(
          restoreRulesNeedKeep(n),
          n == 1 ? '1 person on Auto-record needs a Keep.' : endsWith('2 people on Auto-record need a Keep.'),
        );
        expect(_openSettings, findsNothing);
      });
    }

    testWidgets('flag on, 0: no line', (t) async {
      debugAutoRecordUiOverride = true;
      await _openSheet(t, _result(RulesRestoreOutcome.none));
      expect(find.byKey(const Key('restoreRulesNote0')), findsNothing);
    });

    testWidgets('flag off (dormant): no line even with people to check', (t) async {
      debugAutoRecordUiOverride = false;
      await _openSheet(t, _result(const RulesRestoreOutcome(autoRecordAsAskFirst: 2)));
      expect(find.text(restoreRulesNeedKeep(2)), findsNothing);
      expect(find.byKey(const Key('restoreRulesNote0')), findsNothing);
    });

    testWidgets('both notes together: off note first, then the review line', (t) async {
      debugAutoRecordUiOverride = true;
      await _openSheet(t, _result(const RulesRestoreOutcome(droppedForPrivacy: 1, autoRecordAsAskFirst: 1)));
      expect(find.descendant(of: find.byKey(const Key('restoreRulesNote0')), matching: find.text(hardRestoreOffBody(1))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('restoreRulesNote1')), matching: find.text(restoreRulesNeedKeep(1))), findsOneWidget);
    });
  });

  group('quality bar', () {
    for (final mode in ['light', 'dark']) {
      testWidgets('200% text, $mode: both notes drawn, no overflow, 44 px button', (t) async {
        debugAutoRecordUiOverride = true;
        await _openSheet(t, _result(const RulesRestoreOutcome(droppedForPrivacy: 1, autoRecordAsAskFirst: 2)), scale: 2, mode: mode);
        expect(t.takeException(), isNull);
        expect(find.text(hardRestoreOffBody(1)), findsOneWidget);
        expect(find.text(restoreRulesNeedKeep(2)), findsOneWidget);
        await t.ensureVisible(_openSettings);
        await t.pumpAndSettle();
        final size = t.getSize(_openSettings);
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
        await t.tap(_openSettings);
        await t.pumpAndSettle();
        expect(_pushed, [(Routes.settings, kSettingsTargetCaptureReceiver)]);
      });
    }

    testWidgets('screen reader: the note is one announced unit (title + body), button speaks its label', (t) async {
      final h = t.ensureSemantics();
      await _openSheet(t, _result(const RulesRestoreOutcome(droppedForPrivacy: 2)));
      // RulesNoteBlock is one container + live region: title and body are read together on open.
      expect(
        t.getSemantics(find.text(kHardRestoreOffTitle)),
        matchesSemantics(label: '$kHardRestoreOffTitle\n${hardRestoreOffBody(2)}', isHeader: true, isLiveRegion: true),
      );
      expect(
        t.getSemantics(_openSettings),
        matchesSemantics(
          label: kHardOpenSettings,
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasFocusAction: true,
        ),
      );
      h.dispose();
    });

    testWidgets('right-to-left: drawn without overflow, button still opens Settings', (t) async {
      await _openSheet(t, _result(const RulesRestoreOutcome(droppedForPrivacy: 2)), dir: TextDirection.rtl);
      expect(t.takeException(), isNull);
      expect(find.text(hardRestoreOffBody(2)), findsOneWidget);
      await t.tap(_openSettings);
      await t.pumpAndSettle();
      expect(_pushed, [(Routes.settings, kSettingsTargetCaptureReceiver)]);
    });
  });
}
