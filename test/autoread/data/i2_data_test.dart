// 0.2.2 item 2 redesign, slice I2a: the data-side integration items.
//  - The no-tap message's labels (real_waiting_auto.dart passes them through autoArrivalLabels): the payee name
//    read from the waiting item before the import, made plain (no masked number, no digits), and the category's
//    name; an unknown one is the W2 placeholder, never a number.
//  - anyAskFirstRuleStored respects "Record receiver details": OFF = the rules are hidden, no alert asks, so the
//    category names are not needed (B-HIDE note).
// Mock preferences, invented data only. Dormant: debugAutoRecordUiOverride set per test, reset in tearDown.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/hard_rule_arrival_toast.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = QueuedYesRecorded(itemId: 'a', rowId: 5, amountCents: 45000, categoryId: 7, automatic: true);
const _b = QueuedYesRecorded(itemId: 'b', rowId: 6, amountCents: 1000, categoryId: 9, automatic: true);

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() {
    debugAutoRecordUiOverride = null;
    PillToast.dismissNow();
  });

  group('no-tap message labels (real_waiting_auto.dart call site)', () {
    test('name by item id, category by id; unknown = null', () {
      final l = autoArrivalLabels({'a': 'ALICE WANJIRU', 'b': null}, {7: 'Food'});
      expect(l.nameOf(_a), 'ALICE WANJIRU');
      expect(l.categoryOf(_a), 'Food');
      expect(l.nameOf(_b), isNull);
      expect(l.categoryOf(_b), isNull);
    });

    testWidgets('the message shows the plain payee name (no number) and the category name', (t) async {
      await t.pumpWidget(MaterialApp(navigatorKey: appNavigatorKey, home: const Scaffold(body: SizedBox())));
      final l = autoArrivalLabels({'a': 'ALICE WANJIRU 0722***456'}, {7: 'Food'});
      showAutoArrivalToasts([_a], (_) async {}, nameOf: l.nameOf, categoryOf: l.categoryOf);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(hardAutoArrived('ALICE WANJIRU', 45000, 'Food')), findsOneWidget);
      expect(find.textContaining('0722'), findsNothing);
      expect(find.textContaining('[PM to write'), findsNothing);
    });
  });

  group('anyAskFirstRuleStored and the details switch', () {
    Future<void> withAskFirstRule({required bool detailsOn}) async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsRuleStore();
      expect(
          await store.setLevel(ReceiverType.sendMoney, '254700000001',
              name: 'Tim', level: RuleLevel.askFirst, categoryId: 1, at: DateTime(2026, 11, 26)),
          isTrue);
      final p = await SharedPreferences.getInstance();
      await p.setBool(AppPrefs.keyCaptureIdentityPreference, detailsOn);
    }

    test('details ON (or never set): an Ask first rule counts', () async {
      await withAskFirstRule(detailsOn: true);
      expect(await anyAskFirstRuleStored(), isTrue);
      await (await SharedPreferences.getInstance()).remove(AppPrefs.keyCaptureIdentityPreference);
      expect(await anyAskFirstRuleStored(), isTrue);
    });

    test('details OFF: the rule is hidden, none asks', () async {
      await withAskFirstRule(detailsOn: false);
      expect(await anyAskFirstRuleStored(), isFalse);
    });
  });
}
