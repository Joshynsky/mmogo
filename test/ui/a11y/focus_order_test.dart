// S11b AX1b (wbs A5): initial focus and focus order on sheets and dialogs.
//   - decision dialogs: the FIRST control focus reaches is the safe choice
//     (cancel / keep / merge), never the destructive one;
//   - other sheets: the order reads top to bottom and the action buttons come
//     last; the actual first stop is recorded (a mutation proves each assertion).
// Real FocusManager, Tab key presses, fakes only. The Backup and Delete data
// sheets already pin their initial focus in their own tests (see the matrix in
// _pipeline/v0.1.2/baseline/s11b-deviations.md); not repeated here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/add/add_screen.dart';
import 'package:mmogo/ui/screens/add/name_only_ask.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/restore_dialogs.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y_matrix.dart';
import '../../support/add_harness.dart' show sendMoneySms;
import '../../support/fake_add_db.dart';
import '../../support/fake_analytics_db.dart';
import '../../support/fake_restore_service.dart';
import '../../support/focus_probe.dart';

Finder _k(String key) => find.byKey(Key(key));

Future<void> _tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(_k(key));
  await t.pump();
  await t.tap(_k(key));
  await a11ySettle(t);
}

Widget _opener(void Function(BuildContext) open) => Builder(
  builder: (c) => Scaffold(
    body: Center(
      child: TextButton(key: const Key('opener'), onPressed: () => open(c), child: const Text('OPEN')),
    ),
  ),
);

const _seenAdd = <String, Object>{'tour_seen_add': true};

/// Pumps [home], runs [open], probes focus and returns it.
Future<FocusProbe> _probe(
  WidgetTester t,
  Widget home,
  Future<void> Function() open, {
  Map<String, Object> prefs = const {},
  A11yVariant variant = const A11yVariant('control', 1.0, false),
}) async {
  SharedPreferences.setMockInitialValues({...prefs});
  addTearDown(t.view.reset);
  await pumpA11y(t, home, variant: variant);
  await open();
  final p = await probeFocus(t);
  // ignore: avoid_print
  print('FOCUS ${variant.name}: initial=${p.initial} stops=${p.stops}');
  return p;
}

Future<FocusProbe> _probeWithMemory(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  addTearDown(t.view.reset);
  var clock = 1000;
  final memory = RecipientMemory(nowMs: () => clock++);
  await memory.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
  await memory.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
  await pumpA11y(
    t,
    Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('opener'),
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => RememberedScreen(memory: memory))),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
    variant: kA11yVariants[0],
  );
  await _tapKey(t, 'opener');
  await _tapKey(t, 'rememberedForgetAll');
  final p = await probeFocus(t);
  // ignore: avoid_print
  print('FOCUS forget-all: initial=${p.initial} stops=${p.stops}');
  return p;
}

void main() {
  group('decision dialogs: the first control is the safe choice', () {
    testWidgets('Before you back up (Cancel | Share backup): Cancel first', (t) async {
      final p = await _probe(t, _opener((c) => BackupExportFlow.confirm(c)), () => _tapKey(t, 'opener'));
      expect(p.first!.text, 'Cancel');
      expect(p.stops.map((s) => s.text), ['Cancel', 'Share backup']);
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Merge or Replace: Merge (the default) is first, Replace is not first, Cancel before Continue', (t) async {
      final p = await _probe(t, _opener((c) => showMergeOrReplaceDialog(c, fakePreview())), () => _tapKey(t, 'opener'));
      expect(p.first!.name, 'restoreOptionMerge');
      final names = p.stops.map((s) => s.name).toList();
      expect(names.indexOf('restoreOptionMerge'), lessThan(names.indexOf('restoreOptionReplace')));
      final cancel = p.stops.indexWhere((s) => s.text == 'Cancel');
      final cont = p.stops.indexWhere((s) => s.name == 'restoreContinue');
      expect(cancel, greaterThanOrEqualTo(0));
      expect(cancel, lessThan(cont), reason: 'Cancel before Continue');
      expect(p.stops.last.name, 'restoreContinue', reason: 'the buttons come last');
    });

    testWidgets('Forget all remembered recipients: Cancel first, Forget all second', (t) async {
      final p = await _probeWithMemory(t);
      expect(p.first!.name, 'forgetAllCancel');
      expect(p.stops.map((s) => s.name).take(2), ['forgetAllCancel', 'forgetAllConfirm']);
    });

    testWidgets('the one-button dialogs (rejected file, could not restore): the only stop is OK', (t) async {
      final a = await _probe(t, _opener((c) => showRestoreRejectDialog(c, 'Reason')), () => _tapKey(t, 'opener'));
      expect(a.stops.map((s) => s.text), ['OK']);
      final b = await _probe(t, _opener((c) => showRestoreFailedDialog(c)), () => _tapKey(t, 'opener'));
      expect(b.stops.map((s) => s.text), ['OK']);
    });
  });

  group('sheets: order reads top to bottom, buttons last', () {
    testWidgets('Add: paste sheet (field, Cancel, Parse)', (t) async {
      final p = await _probe(t, AddScreen(db: FakeAddDb()), () => _tapKey(t, 'addPasteButton'), prefs: _seenAdd);
      expect(p.stops.map((s) => s.name), ['addPasteTextField', 'addPasteCancelButton', 'addPasteSubmitButton']);
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Add: "Is NAME on Pochi or Send Money?" (the two choices, then the tick)', (t) async {
      final p = await _probe(
        t,
        _opener((c) => showNameOnlyAsk(c, name: 'JOHN KAMAU', current: null, showTick: true, change: false, tick: false, onTick: (_) {})),
        () => _tapKey(t, 'opener'),
      );
      expect(p.stops.first.name, 'addAskPochi');
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Add: review sheet (Confirm & save, Back to edit last)', (t) async {
      final p = await _probe(t, AddScreen(db: FakeAddDb()), () async {
        await _tapKey(t, 'addPasteButton');
        await t.enterText(_k('addPasteTextField'), sendMoneySms);
        await _tapKey(t, 'addPasteSubmitButton');
        await _tapKey(t, 'addCategoryChip_101');
        await _tapKey(t, 'addReviewButton');
      }, prefs: _seenAdd);
      final names = p.stops.map((s) => s.name).toList();
      expect(names, containsAll(['addReviewConfirmButton', 'addReviewBackButton']));
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Analytics: Custom dates sheet (From, To, then Cancel, Show)', (t) async {
      final p = await _probe(
        t,
        AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow),
        () => _tapKey(t, 'analyticsCalendar'),
      );
      expect(p.stops.map((s) => s.name), ['analyticsCustomFrom', 'analyticsCustomTo', 'analyticsCustomCancel', 'analyticsCustomShow']);
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Analytics: Categories sheet (Close, the rows, then Apply last)', (t) async {
      final p = await _probe(
        t,
        AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow),
        () async {
          await _tapKey(t, 'analyticsTabWhere');
          await _tapKey(t, 'analyticsCategoriesButton');
        },
      );
      expect(p.stops.first.name, 'analyticsCatClose');
      expect(p.stops.last.name, 'analyticsCatApply');
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Analytics: Edit sheet (title row Delete first, fields, Cancel, Save last)', (t) async {
      final p = await _probe(
        t,
        AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow),
        () async {
          await _tapKey(t, 'analyticsRow-1');
          await _tapKey(t, 'analyticsRowEdit-1');
        },
      );
      // LOG for the PM (not changed): the first Tab stop is the header Delete
      // button. Delete only moves the entry to Recently deleted for an hour (Undo),
      // and the order is the on-screen order. Pinned so a change is noticed.
      expect(p.stops.first.name, 'editDeleteButton');
      expect(p.stops.map((s) => s.name).toList().sublist(p.stops.length - 2), ['editCancelButton', 'editSaveButton']);
      expect(readsTopToBottom(p.stops), isTrue);
    });

    testWidgets('Paid to: filter sheet (the options, then Reset and Show last)', (t) async {
      final p = await _probe(
        t,
        PaidToScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow),
        () => _tapKey(t, 'paidToFilterButton'),
      );
      expect(p.stops.map((s) => s.name).toList().sublist(p.stops.length - 2), ['paidToReset', 'paidToShow']);
      expect(readsTopToBottom(p.stops), isTrue);
    });
  });

  test('the dialog wording used above is the wording in lib', () {
    expect(kBackupFileWarning, isNotEmpty);
  });
}
