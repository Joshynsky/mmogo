// U1: the level sheet's ceiling parser (pure) and its helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet_ceiling.dart';

void main() {
  group('parseCeiling table', () {
    final cases = <String, Object?>{
      // text: cents, or the problem
      '': null,
      '   ': null,
      '1': 100,
      '1,000,000': 100000000,
      '1000000': 100000000,
      '1,000,001': CeilingProblem.tooHigh,
      '99999999999999999999999': CeilingProblem.tooHigh,
      'abc': CeilingProblem.bad,
      '0': CeilingProblem.bad,
      '000': CeilingProblem.bad,
      '1,500': 150000,
      ' 20 ': 2000,
      '1.5': CeilingProblem.bad,
      ',': CeilingProblem.bad,
      '-5': CeilingProblem.bad,
      '5 00': CeilingProblem.bad,
      'Ksh 500': CeilingProblem.bad,
      // Fix after self-check: commas only as thousands separators, no leading zeros.
      '12,000': 1200000,
      '999,999': 99999900,
      '1,5,00': CeilingProblem.bad,
      '15,50': CeilingProblem.bad,
      ',500': CeilingProblem.bad,
      '1,50': CeilingProblem.bad,
      '1,': CeilingProblem.bad,
      '1,500,': CeilingProblem.bad,
      '1,,500': CeilingProblem.bad,
      '1500,000': CeilingProblem.bad,
      '0500': CeilingProblem.bad,
      '0,500': CeilingProblem.bad,
      '007': CeilingProblem.bad,
      '01': CeilingProblem.bad,
      '2,000,000': CeilingProblem.tooHigh,
    };
    cases.forEach((text, want) {
      test('"$text" -> $want', () {
        final r = parseCeiling(text);
        if (want is CeilingProblem) {
          expect(r.ok, isFalse);
          expect(r.problem, want);
          expect(r.cents, isNull);
        } else {
          expect(r.ok, isTrue);
          expect(r.cents, want);
        }
      });
    });
  });

  test('every accepted ceiling is valid for the store', () {
    for (final t in ['1', '1,000,000', '1,500', ' 20 ']) {
      expect(isValidCeilingCents(parseCeiling(t).cents), isTrue, reason: t);
    }
  });

  test('field text of a stored ceiling is whole shillings, and parses back', () {
    expect(ceilingFieldText(null), '');
    expect(ceilingFieldText(200000), '2000');
    expect(parseCeiling(ceilingFieldText(200000)).cents, 200000);
  });

  test('problem lines come from the wording file', () {
    expect(ceilingProblemText(CeilingProblem.bad), kHardCeilingError);
    expect(ceilingProblemText(CeilingProblem.tooHigh), kTodoHardCeilingTooHigh);
  });
}
