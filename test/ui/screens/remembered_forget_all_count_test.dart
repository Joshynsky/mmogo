// 0.2.2 item 2 U-FORGET (B-5): the Remembered page's Forget all button is enabled when names + the
// extra tab's people > 0, and looks disabled only at a true 0. A fake tab is used so this test imports
// nothing from the auto-read folder. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/remembered/remembered_extra_tab.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tab without the count interface (the default: names only).
class _PlainTab extends ChangeNotifier implements RememberedExtraTab {
  @override
  Listenable get listenable => this;
  @override
  String get pageTitle => 'Remembered';
  @override
  String get recipientsTabLabel => 'Recipients';
  @override
  String tabLabel() => 'Rules';
  @override
  String get forgetAllLabel => 'Forget all people';
  @override
  String get forgetAllNote => 'The extra sentence.';
  @override
  RememberedExtraHelp get help => const RememberedExtraHelp('Second help', ['second para']);
  @override
  Widget buildBody(BuildContext context) => const Center(child: Text('SECOND BODY'));
  void changed() => notifyListeners();
}

/// A tab holding [rulePeople] people (keys). Like the real tab, a rule person whose key is one of the
/// names is the same person: the extra count leaves them out and the dialog count is names + extra.
class _CountTab extends _PlainTab implements RememberedForgetAllCount, RememberedForgetAllCopy, RememberedForgetHooks {
  _CountTab(this.rulePeople);
  List<String> rulePeople;
  bool failCount = false;
  final List<List<String>> countAsked = [];
  int allForgotten = 0;

  @override
  Future<int> forgetAllExtraPeople(List<String> nameKeys) async {
    countAsked.add(List.of(nameKeys));
    if (failCount) throw StateError('count failed');
    final names = nameKeys.toSet();
    return rulePeople.where((k) => !names.contains(k)).length;
  }

  @override
  Future<RememberedForgetAllText?> forgetAllText(List<String> nameKeys) async {
    final n = nameKeys.toSet().length + await forgetAllExtraPeople(nameKeys);
    return RememberedForgetAllText(title: 'Forget all $n?', body: 'Body', ok: 'Forget all', toast: 'Forgot $n.');
  }

  @override
  Future<void> onAllNamesForgotten() async {
    allForgotten++;
    rulePeople = const [];
  }

  @override
  Future<void> onNameChangedToSendMoney(String key) async {}
  @override
  Future<void> onNameForgotten(String key) async {}
}

Future<RecipientMemory> _memory({bool names = true}) async {
  SharedPreferences.setMockInitialValues({});
  var clock = 1000;
  final m = RecipientMemory(nowMs: () => clock++);
  if (names) {
    await m.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
    await m.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
  }
  return m;
}

Future<void> _pump(WidgetTester t, RecipientMemory m, RememberedExtraTab? tab,
    {double scale = 1, bool dark = false, TextDirection dir = TextDirection.ltr}) async {
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox()); // a second pump in one test builds a fresh page
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
    child: MaterialApp(
      builder: (c, child) => Directionality(
        textDirection: dir,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      ),
      home: RememberedScreen(memory: m, extraTab: tab),
    ),
  ));
  await t.pumpAndSettle();
}

final _bar = find.byKey(const Key('rememberedForgetAll'));

OutlinedButton _button(WidgetTester t) => t.widget<OutlinedButton>(_bar);
bool _enabled(WidgetTester t) => _button(t).onPressed != null;
Color? _side(WidgetTester t) => _button(t).style!.side!.resolve(<WidgetState>{})!.color;
AppPalette _palette(WidgetTester t) => AppPalette.of(t.element(_bar));

void main() {
  testWidgets('rule people and no names: the button is enabled, red-edged, its label from the tab', (t) async {
    await _pump(t, await _memory(names: false), _CountTab(['254700000001', '254700000002']));
    expect(find.byKey(const Key('rememberedEmpty')), findsOneWidget); // the list itself is empty
    expect(_enabled(t), isTrue);
    expect(_side(t), _palette(t).error);
    expect(find.text('Forget all people'), findsOneWidget);
    expect(t.getSemantics(_bar), containsSemantics(isButton: true, isEnabled: true, label: 'Forget all people'));
  });

  testWidgets('rule people and no names: the dialog counts them, Forget all reaches the tab, then 0 = disabled', (t) async {
    final tab = _CountTab(['254700000001', '254700000002']);
    await _pump(t, await _memory(names: false), tab);
    await t.tap(_bar);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('forgetAllDialog')), matching: find.text('Forget all 2?')), findsOneWidget);
    await t.tap(find.byKey(const Key('forgetAllConfirm')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(tab.allForgotten, 1);
    await t.pump(const Duration(seconds: 15)); // the toast's hold runs out
    await t.pumpAndSettle();
    expect(_enabled(t), isFalse); // nobody left: the recount after the run says 0
    expect(_side(t), _palette(t).line);
  });

  testWidgets('no double count: 2 names + 3 rule people, one of them a name -> the dialog says 4, the count got the keys', (t) async {
    final tab = _CountTab(['JANE ATIENO', '254700000001', '254700000002']);
    await _pump(t, await _memory(), tab);
    expect(tab.countAsked.last, unorderedEquals(['JANE ATIENO', 'ZED STORES'])); // the page passed both name keys
    await t.tap(_bar);
    await t.pumpAndSettle();
    final dlg = find.byKey(const Key('forgetAllDialog'));
    expect(find.descendant(of: dlg, matching: find.text('Forget all 4?')), findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('Forget all 5?')), findsNothing); // JANE once, not twice
    for (final name in ['JANE', 'ZED']) {
      expect(find.descendant(of: dlg, matching: find.textContaining(name)), findsNothing, reason: name);
    }
    await t.tap(find.byKey(const Key('forgetAllCancel')));
    await t.pumpAndSettle();
  });

  testWidgets('the disabled look is only at a true 0: no names and no rule people', (t) async {
    await _pump(t, await _memory(names: false), _CountTab(const []));
    expect(_enabled(t), isFalse);
    expect(_side(t), _palette(t).line);
    expect(t.getSemantics(_bar), containsSemantics(isButton: true, isEnabled: false, label: 'Forget all people'));
  });

  testWidgets('a tab without the count (default 0 extra): names only, as before', (t) async {
    await _pump(t, await _memory(names: false), _PlainTab());
    expect(_enabled(t), isFalse);
    await _pump(t, await _memory(), _PlainTab());
    expect(_enabled(t), isTrue);
    expect(_side(t), _palette(t).error);
  });

  testWidgets('no extra tab at all: names only, as before', (t) async {
    await _pump(t, await _memory(names: false), null);
    expect(_enabled(t), isFalse);
  });

  testWidgets('the count cannot be taken: the button stays enabled (not a true 0), the dialog decides', (t) async {
    await _pump(t, await _memory(names: false), _CountTab(const ['254700000001'])..failCount = true);
    expect(_enabled(t), isTrue);
    await t.tap(_bar);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('forgetAllDialog')), findsNothing); // the tab's dialog count also fails
  });

  testWidgets('the tab says it changed: the count is taken again', (t) async {
    final tab = _CountTab(const []);
    await _pump(t, await _memory(names: false), tab);
    expect(_enabled(t), isFalse);
    tab.rulePeople = ['254700000001'];
    tab.changed();
    await t.pumpAndSettle();
    expect(_enabled(t), isTrue);
  });

  testWidgets('back from the second tab: the count is taken again', (t) async {
    final tab = _CountTab(const []);
    await _pump(t, await _memory(names: false), tab);
    await t.tap(find.byKey(const Key('rememberedTab1')));
    await t.pumpAndSettle();
    tab.rulePeople = ['254700000001']; // a rule was set on the second tab
    await t.tap(find.byKey(const Key('rememberedTab0')));
    await t.pumpAndSettle();
    expect(_enabled(t), isTrue);
  });

  for (final dark in [false, true]) {
    for (final dir in TextDirection.values) {
      testWidgets('200% text, ${dark ? 'dark' : 'light'}, ${dir.name}: the bar draws, 44 px, enabled and disabled', (t) async {
        await _pump(t, await _memory(names: false), _CountTab(const ['254700000001']), scale: 2, dark: dark, dir: dir);
        expect(t.takeException(), isNull);
        expect(t.getSize(_bar).height, greaterThanOrEqualTo(44));
        expect(_enabled(t), isTrue);
        await _pump(t, await _memory(names: false), _CountTab(const []), scale: 2, dark: dark, dir: dir);
        expect(t.takeException(), isNull);
        expect(_enabled(t), isFalse);
      });
    }
  }
}
