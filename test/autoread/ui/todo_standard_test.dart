// The standard build keeps the News-only page: no chip bar, no To do words.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/ui/todo_copy.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart';

void main() {
  testWidgets('standard build: News only, no chip bar, no To do words, even for an old chip value', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: NotificationsPage(
        news: FakeNotificationsRepository(const []),
        clock: () => kFakeNow,
        initialChip: NotifChip.todo,
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('notif-chip-todo')), findsNothing);
    expect(find.byKey(const Key('notif-chip-news')), findsNothing); // one chip = no bar
    expect(find.text(kTodoChipLabel), findsNothing);
    expect(find.text(kTodoEmptyTitle), findsNothing);
  }, skip: kAutoReadCompiled);
}
