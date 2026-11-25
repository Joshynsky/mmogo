@Tags(['autoread'])
library;

// 0.2.2 item 2, slice U6 (wave brief section 3, problem 5): FakeRuleStore.setLevel now matches
// PrefsRuleStore.setLevel on the category. A null categoryId clears it on BOTH stores (the fake used to
// keep the old one); passing the stored id keeps it on both. Also the ceiling and the restore mark.
// Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 25, 9);
  final t1 = DateTime.utc(2026, 11, 25, 10);
  const sm = ReceiverType.sendMoney;
  final seed = ReceiverRule(
      type: sm, key: '0722000555', name: 'Tim Otieno', level: RuleLevel.askFirst, categoryId: 4, ceilingCents: 150000,
      autoPending: true, run: 2, runCategoryId: 4, created: t0, changed: t0);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final stores = <String, RuleStore Function()>{'fake': FakeRuleStore.new, 'prefs': PrefsRuleStore.new};
  for (final e in stores.entries) {
    group(e.key, () {
      test('null categoryId clears the category (and the ceiling); the mark is cleared', () async {
        final s = e.value();
        await s.saveRule(seed);
        expect(await s.setLevel(sm, seed.key, name: seed.name, level: RuleLevel.suggested, at: t1), isTrue);
        final r = (await s.get(sm, seed.key))!;
        expect([r.level, r.categoryId, r.ceilingCents, r.autoPending], [RuleLevel.suggested, null, null, false]);
        expect(r.created, t0);
      });

      test('the stored categoryId and ceiling passed explicitly survive', () async {
        final s = e.value();
        await s.saveRule(seed);
        expect(
            await s.setLevel(sm, seed.key,
                name: seed.name, level: RuleLevel.askFirst, categoryId: seed.categoryId, ceilingCents: seed.ceilingCents, at: t1),
            isTrue);
        final r = (await s.get(sm, seed.key))!;
        expect([r.level, r.categoryId, r.ceilingCents, r.autoPending, r.run], [RuleLevel.askFirst, 4, 150000, false, 2]);
      });
    });
  }
}
