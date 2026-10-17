// S11b CB5: the Privacy page and the Updates page get their own semantics,
// focus and 1.3 / dark tests (the H6 review did not cover them).
//   - headings marked header: true, reading order top to bottom
//   - the Privacy "what leaves" expander announced expanded / collapsed
//   - every tappable has a label (no unlabelled tappable)
//   - the first Tab lands on the first control (Back)
//   - 1.3 and dark: Privacy with the expander closed AND open; Updates with 0, 1
//     and many notices, entry + footnote
//   - V4 (B8): the Updates entry heading scrolls with the page, by design
// Fakes only: mock prefs, a fake update client, a fake storage bridge.
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/screens/privacy/privacy_screen.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/updates/fake_update_check_client.dart';
import '../../support/a11y_matrix.dart';
import '../../support/fake_storage_bridge.dart';
import '../../support/semantics_scan.dart';

Finder _k(String key) => find.byKey(Key(key));

final _received = DateTime(2026, 10, 2, 9, 0);

Map<String, Object?> _notice(String tag, String notes, {bool read = false}) => {
  'tag': tag,
  'notes': notes,
  'receivedAt': _received.millisecondsSinceEpoch,
  'read': read,
};

final _longNotes = List.generate(14, (i) => 'Line ${i + 1} of the release notes, invented for this test.').join('\n');

class _Rig {
  _Rig() {
    inbox = UpdatesInbox(installedVersion: () => '0.1.1');
    service = UpdateCheckService(
      clientFactory: () => FakeUpdateCheckClient(result: null, error: null),
      inbox: inbox,
      installedVersion: () => '0.1.1',
    );
  }
  late final UpdatesInbox inbox;
  late final UpdateCheckService service;
}

Map<String, Object> _inboxPrefs(List<Map<String, Object?>> stored) => {
  if (stored.isNotEmpty) 'updates_inbox_v1': jsonEncode(stored),
};

const _control = A11yVariant('control', 1.0, false);

final _routes = <String, WidgetBuilder>{
  Routes.backup: (_) => const Scaffold(body: Text('backup page')),
  Routes.settings: (_) => const Scaffold(body: Text('settings')),
};

/// Pumps the Updates page with [stored] notices in the inbox (loaded first).
Future<void> _pumpUpdates(WidgetTester t, List<Map<String, Object?>> stored, {A11yVariant variant = _control}) async {
  SharedPreferences.setMockInitialValues(_inboxPrefs(stored));
  final rig = _Rig();
  await rig.inbox.load();
  await pumpA11y(t, UpdatesScreen(inbox: rig.inbox, service: rig.service), variant: variant, routes: _routes);
}

Future<void> _pumpPrivacy(WidgetTester t, {A11yVariant variant = _control}) async {
  SharedPreferences.setMockInitialValues({});
  await pumpA11y(t, const PrivacyScreen(), variant: variant, routes: _routes);
}

Future<void> _tabOnceLandsOnBack(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  await t.pump();
  final focus = FocusManager.instance.primaryFocus;
  expect(focus, isNotNull, reason: 'a Tab press focuses something');
  expect(t.getRect(find.byTooltip('Back')).overlaps(focus!.rect), isTrue, reason: 'focus ${focus.rect} is on Back');
}

/// A widget test with the semantics tree on, switched off again at the end (the
/// handle must be disposed before the test ends).
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

void main() {
  setUp(() => StorageBridge.instance = FakeStorageBridge());
  tearDownAll(printA11yLog);

  group('Privacy: semantics and focus', () {
    semanticsTest('section titles are headings, in reading order; the page title too', (t) async {
      await _pumpPrivacy(t);
      final heads = await headingsWhileScrolling(t, find.byType(ListView));
      for (final title in [kPrivacyTitle, kPrivacyStoredTitle, kPrivacyLeavesTitle, kPrivacyBackupFilesTitle, kPrivacyCloudTitle]) {
        expect(heads, contains(title), reason: 'heading "$title" in $heads');
      }
      final order = [kPrivacyStoredTitle, kPrivacyLeavesTitle, kPrivacyBackupFilesTitle, kPrivacyCloudTitle];
      final idx = [for (final o in order) heads.indexOf(o)];
      expect(idx, [...idx]..sort(), reason: 'headings are in reading order: $heads');
    });

    semanticsTest('the expander is announced collapsed, then expanded, then collapsed', (t) async {
      await _pumpPrivacy(t);
      await t.scrollUntilVisible(_k('privacyLeavesToggle'), 300);
      Tristate state() => t.getSemantics(_k('privacyLeavesToggle')).flagsCollection.isExpanded;
      expect(state(), Tristate.isFalse);
      await t.tap(_k('privacyLeavesToggle'));
      await a11ySettle(t);
      expect(state(), Tristate.isTrue);
      await t.tap(_k('privacyLeavesToggle'));
      await a11ySettle(t);
      expect(state(), Tristate.isFalse);
    });

    semanticsTest('no unlabelled tappable (closed and open)', (t) async {
      await _pumpPrivacy(t);
      expect(unlabelledTappables(t), isEmpty);
      await t.scrollUntilVisible(_k('privacyLeavesToggle'), 300);
      await t.tap(_k('privacyLeavesToggle'));
      await a11ySettle(t);
      expect(unlabelledTappables(t), isEmpty);
    });

    testWidgets('the first Tab lands on the first control (Back)', (t) async {
      addTearDown(t.view.reset);
      await _pumpPrivacy(t);
      await _tabOnceLandsOnBack(t);
    });
  });

  group('Updates: semantics and focus', () {
    for (final (name, stored) in [
      ('no notices', <Map<String, Object?>>[]),
      ('one notice', [_notice('v0.1.3', 'Fixes and small improvements.')]),
      ('many notices', [for (var i = 0; i < 6; i++) _notice('v0.1.${3 + i}', _longNotes)]),
    ]) {
      semanticsTest('$name: headings, no unlabelled tappable, switch and buttons labelled', (t) async {
        await _pumpUpdates(t, stored);
        final heads = await headingsWhileScrolling(t, find.byType(ListView), maxSteps: 14);
        expect(heads, contains(kUpdatesTitle), reason: 'the page title');
        expect(heads, contains(kWhatsNewPagerTitle), reason: 'the entry heading');
        if (stored.isNotEmpty) {
          expect(heads.any((x) => x.contains((stored.first['tag']! as String).substring(1))), isTrue, reason: 'a notice title is a heading: $heads');
        }
        expect(unlabelledTappables(t), isEmpty);
        for (var i = 0; i < 30; i++) {
          await t.drag(find.byType(ListView), const Offset(0, 300)); // back to the top
        }
        await a11ySettle(t);
        expect(t.getSemantics(_k('checkNowButton')).label, isNotEmpty);
        // F2 (R51): the row and its switch are ONE node: the title and on/off in a single stop.
        final switchRows = semanticsNodes(t)
            .where((n) => n.label.contains(kUpdatesSwitchTitle) && n.flagsCollection.isToggled != Tristate.none)
            .toList();
        expect(switchRows, hasLength(1), reason: 'one stop for the switch row');
        await t.scrollUntilVisible(_k('whatsNewEntryButton'), 200);
        expect(t.getSemantics(_k('whatsNewEntryButton')).label, kWhatsNewPagerTitle);
        expect(_k('updatesFootnote'), findsNothing, reason: 'R2: the footnote is gone');
      });
    }

    testWidgets('the first Tab lands on the first control (Back)', (t) async {
      addTearDown(t.view.reset);
      await _pumpUpdates(t, const []);
      await _tabOnceLandsOnBack(t);
    });

    testWidgets('V4 (B8): the entry heading scrolls with the page, by design (the mock keeps it in the scroll area)', (t) async {
      addTearDown(t.view.reset);
      final stored = [for (var i = 0; i < 6; i++) _notice('v0.1.${3 + i}', _longNotes)];
      await _pumpUpdates(t, stored);
      await t.scrollUntilVisible(_k('whatsNewEntryTitle'), 200);
      await a11ySettle(t);
      final before = t.getTopLeft(_k('whatsNewEntryTitle')).dy;
      await t.drag(find.byType(ListView), const Offset(0, 120));
      await a11ySettle(t);
      expect(t.getTopLeft(_k('whatsNewEntryTitle')).dy, greaterThan(before), reason: 'it moved down with the page');
    });
  });

  // 1.3 / dark matrix: Privacy closed and open; Updates 0, 1, many notices.
  a11ySubject(
    'Privacy, expander closed',
    home: () => const PrivacyScreen(),
    routes: _routes,
    actions: () => [
      A11yAction('Back', find.byTooltip('Back')),
      A11yAction('Leaves toggle', _k('privacyLeavesToggle')),
    ],
  );
  a11ySubject(
    'Privacy, expander open',
    home: () => const PrivacyScreen(),
    routes: _routes,
    open: (t) async {
      await t.scrollUntilVisible(_k('privacyLeavesToggle'), 300);
      await t.tap(_k('privacyLeavesToggle'));
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Back', find.byTooltip('Back')),
      A11yAction('Leaves toggle', _k('privacyLeavesToggle')),
    ],
  );

  for (final (name, stored) in [
    ('0 notices', <Map<String, Object?>>[]),
    ('1 notice', [_notice('v0.1.3', 'Fixes and small improvements.')]),
    ('many notices', [for (var i = 0; i < 4; i++) _notice('v0.1.${3 + i}', _longNotes)]),
  ]) {
    late _Rig rig;
    a11ySubject(
      'Updates, $name',
      prefs: _inboxPrefs(stored),
      before: () async {
        rig = _Rig();
        await rig.inbox.load();
      },
      home: () => UpdatesScreen(inbox: rig.inbox, service: rig.service),
      routes: _routes,
      actions: () => [
        A11yAction('Back', find.byTooltip('Back')),
        A11yAction('Update switch', _k('updateSwitch')),
        A11yAction('Check for updates now', _k('checkNowButton')),
        A11yAction('See what is new (entry)', _k('whatsNewEntryButton')),
        if (stored.isNotEmpty) A11yAction('See what is new (notice)', _k('noticeSeeWhatsNew')),
        if (stored.length > 1) A11yAction('Show all notes', _k('noticeShowAll')),
      ],
    );
  }
}
