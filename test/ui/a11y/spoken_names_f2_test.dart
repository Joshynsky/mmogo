// F2 (0.1.2 corrections), section A: spoken names for a screen reader.
//   R48  the + (Add) button is ONE node named "Add", a button, selected on Add
//   R49  each bottom tab is a button and says whether it is the selected one
//   R51  a switch row (label + switch) is one stop that reads the label and on/off
//   R53  a tick row (label + checkbox) is one stop that reads the label and checked
// Fakes only: invented data, in-memory prefs, no real database.
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/ui/screens/add/name_only_ask.dart';
import 'package:mmogo/ui/screens/add/receiver_card.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/screens/settings/settings_screen.dart';
import 'package:mmogo/ui/screens/settings/settings_widgets.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/primary_scaffold.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/updates/fake_update_check_client.dart';
import '../../support/add_harness.dart';
import '../../support/fake_add_db.dart';
import '../../support/fake_backup_ui.dart';
import '../../support/fake_delete_data.dart';
import '../../support/fake_storage_bridge.dart';
import '../../support/semantics_scan.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void semanticsTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    final handle = t.ensureSemantics();
    addTearDown(t.view.reset);
    try {
      await body(t);
    } finally {
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    }
  });
}

/// A primary page for [activeIndex] in a tiny app whose Add route is a marker page.
Widget _scaffold(int activeIndex) => MaterialApp(
  routes: {
    Routes.add: (_) => const Scaffold(body: Text('ADD PAGE')),
    Routes.home: (_) => const Scaffold(body: Text('HOME PAGE')),
    Routes.analytics: (_) => const Scaffold(body: Text('ANALYTICS PAGE')),
  },
  home: PrimaryScaffold(title: 'Test', activeIndex: activeIndex, body: const SizedBox()),
);

Iterable<SemanticsNode> _named(WidgetTester t, String label) =>
    semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.label == label);

void main() {
  setUp(() => StorageBridge.instance = FakeStorageBridge());

  group('R48 the + button', () {
    semanticsTest('is exactly one node named Add, a button, with no unnamed stop beside it', (t) async {
      await t.pumpWidget(_scaffold(0));
      await t.pumpAndSettle();
      final adds = _named(t, 'Add').toList();
      expect(adds, hasLength(1), reason: 'one node labelled Add');
      final add = adds.single;
      expect(add.flagsCollection.isButton, isTrue);
      expect(add.flagsCollection.isSelected, Tristate.isFalse, reason: 'not on the Add page');
      expect(add.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // The node sits on the + button, not somewhere else on the page.
      expect(t.getSemantics(find.byKey(const Key('primaryFabRing'))).id, add.id);
      expect(unlabelledTappables(t), isEmpty);
    });

    semanticsTest('is selected on the Add page', (t) async {
      await t.pumpWidget(_scaffold(2));
      await t.pumpAndSettle();
      final add = _named(t, 'Add').single;
      expect(add.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('tapping it still goes to Add', (t) async {
      await t.pumpWidget(_scaffold(0));
      await t.tap(find.byKey(const Key('primaryFab')));
      await t.pumpAndSettle();
      expect(find.text('ADD PAGE'), findsOneWidget);
    });

    semanticsTest('the screen-reader tap action also goes to Add', (t) async {
      await t.pumpWidget(_scaffold(0));
      await t.pumpAndSettle();
      t.semantics.tap(find.semantics.byLabel('Add'));
      await t.pumpAndSettle();
      expect(find.text('ADD PAGE'), findsOneWidget);
    });
  });

  group('R49 bottom tabs', () {
    const tabs = ['Home', 'Analytics', 'Add', 'Paid to', 'Profile'];
    for (final active in [0, 1, 3, 4]) {
      semanticsTest('on ${tabs[active]} only ${tabs[active]} is selected; every tab is a button', (t) async {
        await t.pumpWidget(_scaffold(active));
        await t.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          final nodes = _named(t, tabs[i]).toList();
          expect(nodes, hasLength(1), reason: '${tabs[i]} is one node');
          final n = nodes.single;
          expect(n.flagsCollection.isButton, isTrue, reason: '${tabs[i]} is a button');
          expect(
            n.flagsCollection.isSelected,
            i == active ? Tristate.isTrue : Tristate.isFalse,
            reason: '${tabs[i]} selected only when active=$active',
          );
        }
      });
    }

    testWidgets('tapping a tab still navigates', (t) async {
      await t.pumpWidget(_scaffold(3));
      await t.tap(find.text('Analytics'));
      await t.pumpAndSettle();
      expect(find.text('ANALYTICS PAGE'), findsOneWidget);
    });
  });

  group('R51 switch rows are one stop', () {
    semanticsTest('SettingsToggle: one node with the label, the hint and on/off', (t) async {
      var on = false;
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) => Scaffold(
              body: SettingsToggle(
                palette: AppPalette.light,
                icon: Icons.refresh_rounded,
                label: 'Invented switch row',
                subtitle: 'Its invented explanation.',
                value: on,
                onChanged: (v) => set(() => on = v),
                first: true,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final rows = semanticsNodes(t).where((n) => n.label.contains('Invented switch row')).toList();
      expect(rows, hasLength(1));
      expect(rows.single.hint, contains('Its invented explanation.'));
      expect(rows.single.flagsCollection.isToggled, Tristate.isFalse);
      expect(unnamedStateNodes(t), isEmpty);
      expect(unlabelledTappables(t), isEmpty);
      t.semantics.tap(find.semantics.byLabel(RegExp('Invented switch row')));
      await t.pumpAndSettle();
      expect(on, isTrue);
      expect(semanticsNodes(t).where((n) => n.label.contains('Invented switch row')).single.flagsCollection.isToggled, Tristate.isTrue);
    });

    semanticsTest('Updates page: "Check for updates ..." and its switch are one node reading on/off', (t) async {
      SharedPreferences.setMockInitialValues({});
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      final service = UpdateCheckService(
        clientFactory: () => FakeUpdateCheckClient(result: null, error: null),
        inbox: inbox,
        installedVersion: () => '0.1.1',
      );
      t.view.physicalSize = const Size(420, 3000);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(MaterialApp(home: UpdatesScreen(inbox: inbox, service: service)));
      await t.pumpAndSettle();
      final rows = semanticsNodes(
        t,
      ).where((n) => !n.flagsCollection.isHidden && n.label.contains('Check for updates when you open the app')).toList();
      expect(rows, hasLength(1), reason: 'row and switch are one node');
      expect(rows.single.flagsCollection.isToggled, isNot(Tristate.none));
      expect(unnamedStateNodes(t), isEmpty);
      expect(unlabelledTappables(t), isEmpty);
    });

    semanticsTest('Settings page: every switch row is named (Show withdrawals, Auto-recognize categories)', (t) async {
      useFakeDeleteData();
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(400, 4600);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          home: AppPaletteScope(
            controller: AppPaletteController(),
            child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      final toggles = semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.flagsCollection.isToggled != Tristate.none).toList();
      expect(toggles.length, greaterThanOrEqualTo(2), reason: 'at least the two Settings switches');
      for (final n in toggles) {
        expect(n.label.trim(), isNotEmpty);
      }
      expect(unnamedStateNodes(t), isEmpty);
    });

    semanticsTest('Backup page: the Auto-backup switch row is named', (t) async {
      useFakeBackupUi();
      SharedPreferences.setMockInitialValues({});
      BackupPrefs.pausedNotifier.value = false;
      t.view.physicalSize = const Size(420, 3600);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            key: UniqueKey(),
            loadCounts: () async => const BackupCounts(transactions: 12, userClassifications: 1, receivers: 2, deletedLeftOut: 0),
          ),
        ),
      );
      await t.pumpAndSettle();
      final toggles = semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.flagsCollection.isToggled != Tristate.none).toList();
      expect(toggles, hasLength(1));
      expect(toggles.single.label, contains('Auto'));
      expect(unnamedStateNodes(t), isEmpty);
    });
  });

  group('R53 tick rows are one stop', () {
    semanticsTest('Add: "Also record the receiver\'s name & phone" and its checkbox are one node, checked', (t) async {
      await pumpAdd(t, FakeAddDb(), captureReceiver: true);
      final rows = semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.flagsCollection.isChecked != CheckedState.none && n.label.contains('Also record the receiver')).toList();
      expect(rows, hasLength(1));
      expect(rows.single.label, contains('name & phone'));
      expect(rows.single.flagsCollection.isChecked, CheckedState.isTrue);
      expect(unnamedStateNodes(t), isEmpty, reason: 'no unnamed checkbox on the Add page');
      // Unticking through the one node flips the state.
      t.semantics.tap(find.semantics.byLabel(RegExp('^Also record the receiver')));
      await t.pumpAndSettle();
      final after = semanticsNodes(t).where((n) => n.flagsCollection.isChecked != CheckedState.none && n.label.contains('Also record the receiver')).single;
      expect(after.flagsCollection.isChecked, CheckedState.isFalse);
    });

    semanticsTest('Add: the "Always use" tick is one named node', (t) async {
      final db = FakeAddDb()
        ..counterpartyMap.add({
          'source_type': 'SEND_MONEY',
          'counterparty_key': '0798630424',
          'classification_id': 101,
          'auto_apply': 0,
          'updated_at': 0,
        });
      await pumpAdd(t, db, captureReceiver: true);
      await t.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await t.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await settle(t);
      expect(find.byKey(const Key('addAlwaysUseCheckbox')), findsOneWidget);
      final rows = semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.label.contains('Always use')).toList();
      expect(rows, hasLength(1));
      expect(rows.single.flagsCollection.isChecked, isNot(CheckedState.none));
      expect(unnamedStateNodes(t), isEmpty);
    });

    semanticsTest('ReceiverCard alone: other types give the same single node', (t) async {
      for (final type in ['PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL']) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReceiverCard(
                type: type,
                checked: false,
                name: TextEditingController(),
                sub: TextEditingController(),
                onCheckedChanged: (_) {},
                onFieldChanged: () {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final rows = semanticsNodes(t).where((n) => n.label.contains('Also record')).toList();
        expect(rows, hasLength(1), reason: type);
        expect(rows.single.flagsCollection.isChecked, CheckedState.isFalse, reason: type);
        expect(unnamedStateNodes(t), isEmpty, reason: type);
      }
    });

    semanticsTest('the Pochi / Send Money ask sheet: its tick is one named node', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNameOnlyAsk(
                  context,
                  name: 'JANE ROE',
                  current: null,
                  showTick: true,
                  change: false,
                  tick: false,
                  onTick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final rows = semanticsNodes(t).where((n) => !n.flagsCollection.isHidden && n.label.contains('Remember this choice')).toList();
      expect(rows, hasLength(1));
      expect(rows.single.flagsCollection.isChecked, CheckedState.isFalse);
      expect(unnamedStateNodes(t), isEmpty);
    });
  });
}
