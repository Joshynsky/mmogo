// F6 (0.2.2): Back with the keyboard open closes the keyboard first, the next Back closes the sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/back_closes_keyboard.dart';

void main() {
  setUp(BackClosesKeyboard.install);
  tearDown(BackClosesKeyboard.uninstallForTest);

  Future<void> openSheet(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => showModalBottomSheet<void>(
              context: c,
              isScrollControlled: true,
              builder: (_) => const Padding(padding: EdgeInsets.all(16), child: TextField(key: Key('field'), autofocus: true)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
  }

  testWidgets('keyboard open: first Back unfocuses and keeps the sheet; second Back closes the sheet', (t) async {
    await openSheet(t);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('field')), findsOneWidget, reason: 'sheet still open');
    expect(find.byType(EditableText).evaluate().isNotEmpty, isTrue);
    expect(t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);

    t.view.resetViewInsets(); // the keyboard is gone now
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('field')), findsNothing, reason: 'second Back closes the sheet');
  });

  testWidgets('keyboard closed: Back closes the sheet at once', (t) async {
    await openSheet(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('field')), findsNothing);
  });

  test('keyboardOpen: any view with a bottom inset', () {
    final views = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views;
    expect(BackClosesKeyboard.keyboardOpen(const []), isFalse);
    expect(BackClosesKeyboard.keyboardOpen(views), isFalse);
  });
}
