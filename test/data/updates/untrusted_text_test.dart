// ignore_for_file: text_direction_code_point_in_literal
// B25: the plain-text sanitiser for release notes (criterion 21).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/untrusted_text.dart';

void main() {
  String s(String x) => UntrustedText.sanitize(x);

  test('plain text passes through unchanged', () {
    expect(s('Fixes a bug.\nAdds backup.'), 'Fixes a bug.\nAdds backup.');
  });

  test('control characters stripped, tab becomes a space, CR dropped, newline kept', () {
    expect(s('a\u0000b\u0007c\u001Bd\u007Fe\u0085f\u009Fg'), 'abcdefg');
    expect(s('a\tb'), 'a b');
    expect(s('one\r\ntwo'), 'one\ntwo');
  });

  test('bidi, zero-width and separator characters stripped', () {
    const hostile = 'a‮b‪c‭d⁦e⁩f​g‌h‍i﻿j‎k‏l m n؜o⁠p';
    expect(s(hostile), 'abcdefghijklmnop');
  });

  test('tag characters and lone surrogates stripped, emoji kept', () {
    expect(s('ok \u{1F600} \u{E0041}x'), 'ok \u{1F600} x');
    expect(s('a\uD800b'), 'ab');
  });

  test('links are plain characters (nothing is removed or turned into anything)', () {
    expect(s('See https://evil.example/apk and [x](http://a.b)'),
        'See https://evil.example/apk and [x](http://a.b)');
  });

  test('empty and whitespace-only give empty', () {
    expect(s(''), '');
    expect(s('  \n\t ​ '), '');
  });

  test('exactly 30 lines kept, 31 cut with an ellipsis', () {
    final thirty = List.generate(30, (i) => 'l$i').join('\n');
    expect(s(thirty), thirty);
    final out = s('$thirty\nl30');
    expect(out.split('\n').length, 30);
    expect(out.endsWith('…'), isTrue);
    expect(out, isNot(contains('l30')));
  });

  test('1,500 characters kept, 1,501 cut to 1,500 with an ellipsis', () {
    final ok = 'a' * 1500;
    expect(s(ok), ok);
    final out = s('a' * 1501);
    expect(out.runes.length, 1500);
    expect(out.endsWith('…'), isTrue);
  });

  test('cap counts characters, not UTF-16 units (no split emoji)', () {
    final out = s('\u{1F600}' * 2000);
    expect(out.runes.length, 1500);
    expect(out.runes.every((r) => r == 0x1F600 || r == 0x2026), isTrue);
  });

  test('idempotent on hostile and over-long input', () {
    final inputs = [
      'x‮\u0000y',
      List.generate(80, (i) => 'line $i ' * 40).join('\n'),
      'a' * 5000,
      '${List.generate(31, (i) => 'b' * 100).join('\n')}\n',
      '  padded  \n\n\n',
    ];
    for (final i in inputs) {
      final once = s(i);
      expect(s(once), once);
      expect(once.split('\n').length, lessThanOrEqualTo(30));
      expect(once.runes.length, lessThanOrEqualTo(1500));
    }
  });
}
