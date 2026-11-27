// 0.2.1 #10: a What's new link opens Settings; Back returns to the same page, same open item, same scroll place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/ui/screens/settings/settings_targets.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';

Future<List<String?>> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  WhatsNewProcess.resetForTest();
  final targets = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      routes: {'/settings': (_) => Scaffold(appBar: AppBar(title: const Text('SETTINGS STUB')))},
      home: Builder(
        builder: (context) => ElevatedButton(
          key: const Key('go'),
          onPressed: () => showWhatsNewPager(
            context,
            readOnly: true,
            onOpenSettings: (t) {
              targets.add(t);
              Navigator.of(context).pushNamed('/settings');
            },
            onOpenBackup: () {},
          ),
          child: const Text('HOME'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
  return targets;
}

double _offset(WidgetTester t) =>
    t.state<ScrollableState>(find.descendant(of: find.byKey(const Key('whatsNewScroll')), matching: find.byType(Scrollable))).position.pixels;

Future<void> _openItem(WidgetTester tester, String id, Key link) async {
  final head = find.byKey(Key('whatsNewItemHead-$id'));
  await tester.ensureVisible(head);
  await tester.pumpAndSettle();
  if (find.byKey(Key('whatsNewItemBody-$id')).evaluate().isEmpty) {
    await tester.tap(head);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(link));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Auto-record link: Back from Settings returns to the same item, open, at the same scroll place', (tester) async {
    final targets = await _pumpHome(tester);
    await _openItem(tester, 'autorecord', const Key('whatsNewCalSettings'));
    final before = _offset(tester);
    await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS STUB'), findsOneWidget);
    expect(targets, [kSettingsTargetRemembered]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('whatsNewPager')), findsOneWidget);
    expect(find.byKey(const Key('whatsNewItemBody-autorecord')), findsOneWidget, reason: 'the item is still open');
    expect(_offset(tester), before, reason: 'not back at the top');
    expect(tester.getTopLeft(find.byKey(const Key('whatsNewCalSettings'))).dy, inInclusiveRange(0, 700));
    // Back once more closes the page itself.
    await tester.tap(find.byKey(const Key('whatsNewBack')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('whatsNewPager')), findsNothing);
  }, skip: !kAutoReadCompiled);

  testWidgets('standard build: no Reading link anywhere on the page', (tester) async {
    await _pumpHome(tester);
    expect(find.byKey(const Key('whatsNewReadingSettings')), findsNothing);
  }, skip: kAutoReadCompiled);
}
