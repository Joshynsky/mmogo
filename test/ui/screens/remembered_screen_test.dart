// 0.1.2 S9a: the Remembered recipients page (signed mock remembered.html).
// Invented names only. Names must never reach a snackbar, an error line or a
// log: those are checked by reading every Text on screen and every SnackBar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A memory whose writes fail (the list still reads).
class _FailingPrefs implements SharedPreferences {
  _FailingPrefs(this._real);
  final SharedPreferences _real;
  @override
  String? getString(String key) => _real.getString(key);
  @override
  bool containsKey(String key) => _real.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async => false;
  @override
  Future<bool> remove(String key) async => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _names = ['JANE ATIENO', 'ZED STORES', 'OTIENO KIOSK'];

late int _clock;

RecipientMemory _mem() => RecipientMemory(nowMs: () => _clock++);

Future<RecipientMemory> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  _clock = 1000;
  final m = _mem();
  await m.remember(_names[0], SmsSourceType.pochi, recordDetailsOn: true); // oldest
  await m.remember(_names[1], SmsSourceType.sendMoney, recordDetailsOn: true);
  await m.remember(_names[2], SmsSourceType.pochi, recordDetailsOn: true); // newest
  return m;
}

Future<void> _pump(WidgetTester tester, RecipientMemory memory, {double scale = 1.0, bool dark = false}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
      child: MaterialApp(
        builder: (c, child) =>
            MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RememberedScreen(memory: memory))),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

List<String> _rowNames(WidgetTester t) => [
  for (final w in t.widgetList<Text>(find.byKey(const Key('rememberedName')))) w.data!,
];

/// Every string drawn by any Text on screen, except the row names themselves.
String _allTextOutsideRows(WidgetTester t) {
  final inRows = find.byKey(const Key('rememberedName'));
  final out = StringBuffer();
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    if (inRows.evaluate().any((r) => r.widget == w)) continue;
    out.writeln(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  return out.toString();
}

void main() {
  testWidgets('lists the stored names newest first, upper case, with their type; copy from the mock', (tester) async {
    await _pump(tester, await _seeded());
    expect(_rowNames(tester), ['OTIENO KIOSK', 'ZED STORES', 'JANE ATIENO']);
    final tags = [
      for (final w in tester.widgetList<Container>(find.byKey(const Key('rememberedTag'))))
        ((w.child as Text).data!),
    ];
    expect(tags, ['Pochi', 'Send Money', 'Pochi']);
    expect(find.text('Remembered recipients'), findsWidgets);
    expect(
      find.text('People and businesses you told us are Send Money or Pochi. Kept on this phone only. Not in backups. Not shared.'),
      findsOneWidget,
    );
    expect(find.text('Change to Send Money'), findsNWidgets(2));
    expect(find.text('Change to Pochi'), findsOneWidget);
    expect(find.text('Forget'), findsNWidgets(3));
    expect(find.text('Forget all'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing, reason: 'no Add button on a secondary page');
  });

  testWidgets('F2: a plain line says names stay until forgotten, even with the switch off', (tester) async {
    await _pump(tester, await _seeded());
    expect(
      find.text('Remembered names stay until you forget them, even if you turn off “Also record the receiver’s details”.'),
      findsOneWidget,
    );
  });

  testWidgets('Forget one: that name goes, the others stay in order, a counts-only snackbar shows', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    await tester.tap(find.byKey(const Key('rememberedForget')).at(1)); // ZED STORES
    await tester.pumpAndSettle();
    expect(_rowNames(tester), ['OTIENO KIOSK', 'JANE ATIENO']);
    expect((await m.list()).map((e) => e.key), ['OTIENO KIOSK', 'JANE ATIENO']);
    expect(find.text('Forgot 1 recipient'), findsOneWidget);
    for (final n in _names) {
      expect(_allTextOutsideRows(tester).contains(n), isFalse, reason: 'no name in a message');
    }
  });

  testWidgets('Forget all asks first; Cancel keeps everything', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    expect(find.text('Forget all remembered recipients?'), findsOneWidget);
    expect(find.text('We will ask again next time.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('forgetAllCancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgetAllDialog')), findsNothing);
    expect(await m.list(), hasLength(3));
    expect(_rowNames(tester), hasLength(3));
  });

  testWidgets('a tap outside the dialog and the Back button both mean Cancel', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgetAllDialog')), findsNothing);
    expect(await m.list(), hasLength(3));

    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // Back closes the dialog only
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgetAllDialog')), findsNothing);
    expect(find.byKey(const Key('rememberedForgetAll')), findsOneWidget, reason: 'still on the page');
    expect(await m.list(), hasLength(3));
  });

  testWidgets('Forget all, confirmed: empty state, button off, "Forgot 3 recipients", storage emptied', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forgetAllConfirm')));
    await tester.pumpAndSettle();
    expect(await m.list(), isEmpty);
    expect((await SharedPreferences.getInstance()).containsKey('recipient_types_v1'), isFalse);
    expect(find.byKey(const Key('rememberedEmpty')), findsOneWidget);
    expect(find.text('Forgot 3 recipients'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('rememberedForgetAll'))).onPressed, isNull);
    for (final n in _names) {
      expect(_allTextOutsideRows(tester).contains(n), isFalse);
    }
  });

  testWidgets('R28: the "Forgot N" toast lasts about 2 seconds, then goes (no Undo)', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    await tester.tap(find.byKey(const Key('rememberedForgetAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forgetAllConfirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Forgot 3 recipients'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 2));
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
    // Not yet gone at 1.5 s, gone shortly after 2 s (the default 4 s would still show it).
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Forgot 3 recipients'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Forgot 3 recipients'), findsNothing);
  });

  testWidgets('empty state: the mock text, and no rows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, _mem());
    expect(find.text('Nothing remembered yet.'), findsOneWidget);
    expect(find.text('When a message has a name but no phone number, we ask once and can remember your answer.'), findsOneWidget);
    expect(find.text('Names are remembered only when “Also record the receiver’s details” is on.'), findsOneWidget);
    expect(find.byKey(const Key('rememberedName')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('rememberedForgetAll'))).onPressed, isNull);
  });

  testWidgets('Change to the other type: the row keeps its place and its date, only the tag changes', (tester) async {
    final m = await _seeded();
    await _pump(tester, m);
    final before = await m.list();
    await tester.tap(find.byKey(const Key('rememberedChange')).at(1)); // the middle row, ZED STORES (Send Money)
    await tester.pumpAndSettle();
    expect(_rowNames(tester), ['OTIENO KIOSK', 'ZED STORES', 'JANE ATIENO'], reason: 'the list stays where it was');
    final after = await m.list();
    expect(after[1].key, 'ZED STORES');
    expect(after[1].rule.type, SmsSourceType.pochi);
    expect(after[1].rule.at, before[1].rule.at, reason: 'the date is not bumped');
    final tags = [for (final w in tester.widgetList<Container>(find.byKey(const Key('rememberedTag')))) ((w.child as Text).data!)];
    expect(tags, ['Pochi', 'Pochi', 'Pochi']);
    expect(find.text('Change to Send Money'), findsNWidgets(3));
  });

  testWidgets('Change keeps the scroll position (a long list, change a row far down)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _clock = 1000;
    final m = _mem();
    for (var i = 0; i < 30; i++) {
      await m.remember('PERSON ${i.toString().padLeft(2, '0')}', SmsSourceType.pochi, recordDetailsOn: true);
    }
    await _pump(tester, m);
    await tester.drag(find.byKey(const Key('rememberedScroll')), const Offset(0, -700));
    await tester.pumpAndSettle();
    double offset() => tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('rememberedScroll')), matching: find.byType(Scrollable))).position.pixels;
    final o = offset();
    expect(o, greaterThan(300));
    // A Change button that is really on screen (the first ones scrolled off).
    final all = find.byKey(const Key('rememberedChange'));
    final onScreen = [
      for (var i = 0; i < all.evaluate().length; i++)
        if (tester.getCenter(all.at(i)).dy > 150 && tester.getCenter(all.at(i)).dy < 800) i,
    ];
    expect(onScreen, isNotEmpty);
    final typeBefore = tester.widgetList<Container>(find.byKey(const Key('rememberedTag'))).map((w) => (w.child as Text).data).toList();
    await tester.tap(all.at(onScreen.first));
    await tester.pumpAndSettle();
    expect(offset(), o);
    final typeAfter = tester.widgetList<Container>(find.byKey(const Key('rememberedTag'))).map((w) => (w.child as Text).data).toList();
    expect(typeAfter, isNot(typeBefore), reason: 'the change really happened');
  });

  testWidgets('error pattern A: a failed write shows a red line with no name, no snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _clock = 1000;
    final good = _mem();
    await good.remember(_names[0], SmsSourceType.pochi, recordDetailsOn: true);
    final real = await SharedPreferences.getInstance();
    final bad = RecipientMemory(prefs: () async => _FailingPrefs(real), nowMs: () => _clock++);
    await _pump(tester, bad);
    await tester.tap(find.byKey(const Key('rememberedForget')));
    await tester.pumpAndSettle();
    expect(find.text('Could not update the remembered recipients. Please try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_rowNames(tester), [_names[0]], reason: 'nothing was forgotten');
    expect(_allTextOutsideRows(tester).contains(_names[0]), isFalse);
    // Change fails the same way (retype goes through setString).
    await tester.tap(find.byKey(const Key('rememberedChange')));
    await tester.pumpAndSettle();
    expect(find.text('Could not update the remembered recipients. Please try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('screen-reader labels: "Forget NAME" is a label only', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, await _seeded());
    expect(find.bySemanticsLabel('Forget ZED STORES'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('44 px hit areas, 1.3 text scale, dark theme', (tester) async {
    final m = await _seeded();
    await _pump(tester, m, scale: 1.3, dark: true);
    expect(tester.takeException(), isNull);
    for (final k in ['rememberedChange', 'rememberedForget']) {
      for (final e in tester.widgetList(find.byKey(Key(k))).toList().asMap().keys) {
        expect(tester.getSize(find.byKey(Key(k)).at(e)).height, greaterThanOrEqualTo(44), reason: k);
      }
    }
    expect(tester.getSize(find.byKey(const Key('rememberedForgetAll'))).height, greaterThanOrEqualTo(44));
  });

  test('the page source has no print, debugPrint or log call', () {
    final code = File('lib/ui/screens/remembered/remembered_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final logCall = RegExp(r'\b(print|debugPrint|log)\s*\(');
    expect(logCall.hasMatch(code), isFalse);
    expect(logCall.hasMatch("print('x');"), isTrue, reason: 'negative control: the guard sees a bad line');
    // A message built from a key or name would interpolate entry.key / e.key
    // into a Text outside the row or into a SnackBar.
    expect(RegExp(r'SnackBar\([^)]*(\.key|name)').hasMatch(code), isFalse);
  });
}
