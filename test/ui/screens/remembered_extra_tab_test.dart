// The Remembered page with and without a second tab. A fake tab is used here
// so this test imports nothing from the auto-read folder. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/copy/settings_copy.dart';
import 'package:mmogo/ui/screens/remembered/remembered_extra_tab.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTab extends ChangeNotifier implements RememberedExtraTab {
  int count = 0;
  @override
  Listenable get listenable => this;
  @override
  String get pageTitle => 'Remembered';
  @override
  String get recipientsTabLabel => 'Recipients';
  @override
  String tabLabel() => 'Second tab $count';
  @override
  String get forgetAllLabel => 'Forget all recipients';
  @override
  String get forgetAllNote => 'The extra sentence.';
  @override
  RememberedExtraHelp get help => const RememberedExtraHelp('Second help', ['second para']);
  @override
  Widget buildBody(BuildContext context) => const Center(child: Text('SECOND BODY'));
  void bump() {
    count++;
    notifyListeners();
  }
}

Future<RecipientMemory> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  var clock = 1000;
  final m = RecipientMemory(nowMs: () => clock++);
  await m.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
  await m.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
  return m;
}

Future<void> _pump(
  WidgetTester tester,
  RecipientMemory memory,
  RememberedExtraTab? extra, {
  double scale = 1.0,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
      child: MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RememberedScreen(memory: memory, extraTab: extra),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no extra tab: the page is the plain one, no tabs', (tester) async {
    await _pump(tester, await _seeded(), null);
    expect(find.text(kRememberedTitle), findsOneWidget);
    expect(find.byKey(const Key('rememberedTab0')), findsNothing);
    expect(find.byKey(const Key('rememberedTab1')), findsNothing);
    expect(find.byType(IndexedStack), findsNothing);
    expect(find.text(kForgetAll), findsOneWidget);
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    expect(find.text(kForgetAllBody), findsOneWidget);
    expect(find.text('The extra sentence.'), findsNothing);
  });

  testWidgets('with an extra tab: title, two tabs, label follows the listenable', (tester) async {
    final tab = _FakeTab();
    await _pump(tester, await _seeded(), tab);
    expect(find.text('Remembered'), findsOneWidget);
    expect(find.text(kRememberedTitle), findsNothing);
    expect(find.text('Recipients'), findsOneWidget);
    expect(find.text('Second tab 0'), findsOneWidget);
    tab.bump();
    await tester.pump();
    expect(find.text('Second tab 1'), findsOneWidget);
    expect(find.text('Second tab 0'), findsNothing);
    expect(find.bySemanticsLabel('About this page'), findsOneWidget); // the help button stays
  });

  testWidgets('one question mark on each tab; the second tab opens its own help', (tester) async {
    await _pump(tester, await _seeded(), _FakeTab());
    expect(find.byKey(const Key('helpButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('helpButton')));
    await tester.pumpAndSettle();
    expect(find.text(kRememberedHelpTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('helpSheetClose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rememberedTab1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('helpButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('helpButton')));
    await tester.pumpAndSettle();
    expect(find.text('Second help'), findsOneWidget);
    expect(find.text('second para'), findsOneWidget);
    expect(find.text(kRememberedHelpTitle), findsNothing);
  });

  testWidgets('Forget all bar and the list are on tab 1 only', (tester) async {
    await _pump(tester, await _seeded(), _FakeTab());
    expect(find.byKey(const Key('rememberedForgetAll')), findsOneWidget);
    expect(find.text('Forget all recipients'), findsOneWidget);
    expect(find.text('SECOND BODY'), findsNothing);
    await tester.tap(find.byKey(const Key('rememberedTab1')));
    await tester.pumpAndSettle();
    expect(find.text('SECOND BODY'), findsOneWidget);
    expect(find.byKey(const Key('rememberedForgetAll')), findsNothing);
    expect(find.byKey(const Key('rememberedName')), findsNothing);
    await tester.tap(find.byKey(const Key('rememberedTab0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rememberedForgetAll')), findsOneWidget);
    expect(find.byKey(const Key('rememberedName')), findsNWidgets(2));
  });

  testWidgets('tab 1 keeps its scroll place after a visit to tab 2', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var clock = 1000;
    final m = RecipientMemory(nowMs: () => clock++);
    for (var i = 0; i < 14; i++) {
      await m.remember('NAME ${String.fromCharCode(65 + i)}', SmsSourceType.pochi, recordDetailsOn: true);
    }
    await _pump(tester, m, _FakeTab());
    await tester.drag(find.byKey(const Key('rememberedScroll')), const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('rememberedScroll')), matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(before, greaterThan(0));
    await tester.tap(find.byKey(const Key('rememberedTab1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rememberedTab0')));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('rememberedScroll')), matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(after, before);
  });

  testWidgets('the Forget all dialog adds the extra sentence', (tester) async {
    await _pump(tester, await _seeded(), _FakeTab());
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    expect(find.text(kForgetAllBody), findsOneWidget);
    expect(find.text('The extra sentence.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('forgetAllConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rememberedName')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('large text (1.3) ${dark ? 'dark' : 'light'}: both tabs draw without overflow', (tester) async {
      await _pump(tester, await _seeded(), _FakeTab()..count = 2, scale: 1.3, dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('rememberedTab1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('rememberedTab1'))).height, greaterThanOrEqualTo(44));
    });
  }
}
