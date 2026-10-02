// B28 (as redefined by the PM): Settings has only an "Updates" row. Its
// subtitle says whether checking is on and when it last worked, or that a
// new version is out; a red dot shows while any notice is unread; it opens the
// Updates page (where the switch, Check now and Last checked live) and
// re-reads when that page is closed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/ui/screens/settings/updates_section.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _at = DateTime(2026, 10, 2, 9, 0);

Map<String, Object?> _notice(String tag, {bool read = false, bool welcome = false}) => {
  'tag': tag,
  'notes': '',
  'receivedAt': _at.millisecondsSinceEpoch,
  'read': read,
  if (welcome) 'welcome': true,
};

Future<UpdatesInbox> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  List<Map<String, Object?>> stored = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (stored.isNotEmpty) 'updates_inbox_v1': jsonEncode(stored),
  });
  final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
  await inbox.load();
  await tester.pumpWidget(
    MaterialApp(
      routes: {Routes.updates: (_) => UpdatesScreen(inbox: inbox)},
      home: Scaffold(body: UpdatesSection(palette: AppPalette.light, inbox: inbox)),
    ),
  );
  await tester.pumpAndSettle();
  return inbox;
}

void main() {
  testWidgets('there is one Updates row and no switch or Check button in Settings', (tester) async {
    await _pump(tester);
    expect(find.text('UPDATES AND FEEDBACK'), findsOneWidget);
    expect(find.text('Updates'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Check for updates now'), findsNothing);
  });

  testWidgets('on, never checked: "Checking is on. Not checked yet."', (tester) async {
    await _pump(tester);
    expect(find.text('Checking is on. Not checked yet.'), findsOneWidget);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsNothing);
  });

  testWidgets('on, checked: "Checking is on. Last checked <date>."', (tester) async {
    await _pump(tester, prefs: {'update_last_check_at': _at.millisecondsSinceEpoch});
    expect(find.text('Checking is on. Last checked 2 Oct 2026.'), findsOneWidget);
  });

  testWidgets('off: "Checking is off"', (tester) async {
    await _pump(tester, prefs: {'update_check_enabled': false});
    expect(find.text('Checking is off'), findsOneWidget);
  });

  testWidgets('an unread release: "A new version is out" and the red dot', (tester) async {
    await _pump(tester, stored: [_notice('v0.2.0')]);
    expect(find.text('A new version is out'), findsOneWidget);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsOneWidget);
  });

  testWidgets('an unread welcome notice shows the dot but does not claim a new version', (tester) async {
    await _pump(tester, stored: [_notice('Welcome', welcome: true)]);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsOneWidget);
    expect(find.text('A new version is out'), findsNothing);
    expect(find.textContaining('Checking is on.'), findsOneWidget);
  });

  testWidgets('a read release: no dot, back to the checking line', (tester) async {
    await _pump(tester, stored: [_notice('v0.2.0', read: true)]);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsNothing);
    expect(find.text('A new version is out'), findsNothing);
  });

  testWidgets('opening the page and coming back clears the dot and re-reads the switch', (tester) async {
    final inbox = await _pump(tester, stored: [_notice('v0.2.0')]);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsOneWidget);

    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    expect(find.text('Check for updates now'), findsOneWidget);
    await tester.tap(find.byType(Switch)); // turn checking off on the page
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(inbox.unreadCount.value, 0);
    expect(find.byKey(const Key('settingsRowUnreadDot')), findsNothing);
    expect(find.text('Checking is off'), findsOneWidget);
  });
}
