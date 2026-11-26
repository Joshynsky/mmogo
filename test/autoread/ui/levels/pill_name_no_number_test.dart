@Tags(['autoread'])
library;

// I2c (0.2.2 item 2, sign-off "Pill: no phone number"): every call into the change pill (RuleChangeNotice.show)
// gets a name with no digit and no '*', also for a nameless Send Money person whose name is the masked number
// (Set up's displayName, "0722***555") or the full number (a rule named by its key, "0722123555"). Plain names
// reach the pill unchanged. Call sites: saveLevelChoice (level_sheet_open.dart, via levelNoticeName) and
// SuggestionsController.confirm / confirmAuto (suggestions_controller.dart). Plus the shared helper itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/plain_name.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet_open.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/notifications/suggestions_controller.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/redesign_fakes.dart';

const _masked = '0722***555';
const _full = '0722123555';
final _digitOrStar = RegExp(r'[0-9*]');

void _expectNoNumber(String s) => expect(_digitOrStar.hasMatch(s), isFalse, reason: 'pill name "$s"');

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  group('shared helper (plain_name.dart)', () {
    test('a masked or full number leaves nothing: the placeholder, which holds no digit or star', () {
      for (final raw in [_masked, _full, '  $_full  ', '', null]) {
        expect(plainPersonName(raw), isNull, reason: '$raw');
        _expectNoNumber(pillPersonName(raw));
      }
      expect(pillPersonName(_masked), pillPersonName(null));
    });

    test('plain names are kept; a number next to a name is dropped', () {
      expect(pillPersonName('Tim Otieno'), 'Tim Otieno');
      expect(pillPersonName('  Tim   Otieno '), 'Tim Otieno');
      expect(pillPersonName('Tim Otieno $_masked'), 'Tim Otieno');
    });
  });

  group('CALL-SITE saveLevelChoice (level sheet)', () {
    for (final raw in [_masked, _full]) {
      for (final level in RuleLevel.values) {
        test('nameless Send Money "$raw" at ${level.name}: no digit and no star reaches the pill', () async {
          final store = FakeRuleStore();
          // A stored rule so Suggested stores a change too (and so shows the pill).
          await store.setLevel(ReceiverType.sendMoney, _full,
              name: raw, level: RuleLevel.askFirst, categoryId: 1, at: kHardTestNow);
          final notice = FakeCategoryRuleChangeNotice();
          final x = LevelPerson(type: ReceiverType.sendMoney, key: _full, name: raw, level: RuleLevel.askFirst);
          await saveLevelChoice(redesignTestDeps(store: store, notice: notice), x, level, 1,
              level == RuleLevel.autoRecord ? 150000 : null,
              notify: true);
          _expectNoNumber(notice.calls.single.name);
        });
      }
    }

    test('a plain name reaches the pill unchanged', () async {
      final notice = FakeCategoryRuleChangeNotice();
      const x = LevelPerson(type: ReceiverType.sendMoney, key: _full, name: 'Tim Otieno', level: RuleLevel.suggested);
      await saveLevelChoice(redesignTestDeps(notice: notice), x, RuleLevel.askFirst, 1, null, notify: true);
      expect(notice.calls.single.name, 'Tim Otieno');
    });

    test('levelNoticeName: masked and full number give no digit and no star', () {
      for (final raw in [_masked, _full]) {
        _expectNoNumber(
            levelNoticeName(LevelPerson(type: ReceiverType.sendMoney, key: _full, name: raw, level: RuleLevel.suggested)));
      }
    });
  });

  group('CALL-SITE SuggestionsController (offer card)', () {
    Future<CategoryNoticeCall> run(String name, {required bool auto}) async {
      final o = Offer(type: ReceiverType.sendMoney, key: _full, name: name, categoryId: 5, run: 3);
      final notice = FakeCategoryRuleChangeNotice();
      final c = SuggestionsController(
          engine: FakeRuleEngine(offers: [o]), store: FakeRuleStore(), clock: () => kHardTestNow, notice: notice);
      final ok = auto ? await c.confirmAuto(o, categoryName: 'Food') : await c.confirm(o, categoryName: 'Food');
      c.dispose();
      expect(ok, isTrue);
      return notice.calls.single;
    }

    for (final raw in [_masked, _full]) {
      test('confirm (Ask first), nameless "$raw": no digit and no star reaches the pill', () async {
        _expectNoNumber((await run(raw, auto: false)).name);
      });
      test('confirmAuto (Auto-record), nameless "$raw": no digit and no star reaches the pill', () async {
        _expectNoNumber((await run(raw, auto: true)).name);
      });
    }

    test('plain names reach the pill unchanged (both buttons)', () async {
      expect((await run('PETER MWANGI', auto: false)).name, 'PETER MWANGI');
      expect((await run('PETER MWANGI', auto: true)).name, 'PETER MWANGI');
    });
  });
}
