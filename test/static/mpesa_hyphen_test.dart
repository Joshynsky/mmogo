// S11b AX1a (wbs AX1, defect F-8, addendum B3): visible prose writes "M-Pesa"
// with the non-breaking hyphen (written as the escape `\u2011` in source, so
// source_encoding_test stays green and the file stays plain ASCII). The pager
// wrapped "M-Pesa" at 360 px; U+2011 cannot break.
//
// Deviation (B3): the signed mocks use an ordinary hyphen. The wbs row wins.
//
// Scan scope: lib/ui code lines (whole-line and trailing comments are skipped).
// Out of scope on purpose: domain/parsing (the parser message and regexes must
// match real SMS text), export and backup strings, and test fixtures.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lines of [sources] (path -> text) where code (not a comment) holds an
/// ordinary-hyphen "M-Pesa", as `path:line`.
List<String> ordinaryMpesaHits(Map<String, String> sources, {Map<String, String> allow = const {}}) {
  final hits = <String>[];
  sources.forEach((path, text) {
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      // Drop a trailing `// ...` comment: the first `//` with an even number of
      // quote characters before it (so a `//` inside a string stays).
      for (var j = 0, quotes = 0; j < line.length - 1; j++) {
        final c = line[j];
        if (c == "'" || c == '"') quotes++;
        if (quotes.isEven && c == '/' && line[j + 1] == '/') {
          line = line.substring(0, j);
          break;
        }
      }
      if (!line.contains('M-Pesa')) continue;
      final why = allow[path];
      if (why != null && line.contains(why)) continue;
      hits.add('$path:${i + 1}');
    }
  });
  return hits;
}

/// Documented exceptions: (file) -> a substring of the line that may keep the
/// ordinary hyphen. These are Semantics labels (read aloud, never wrapped).
const kOrdinaryHyphenAllow = <String, String>{
  'lib/ui/screens/home/summary_card.dart': "'Transaction cost, all M-Pesa,",
};

Map<String, String> _uiSources() {
  final out = <String, String>{};
  for (final e in Directory('lib/ui').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) out[e.path.replaceAll('\\', '/')] = e.readAsStringSync();
  }
  return out;
}

void main() {
  test('no visible-prose literal in lib/ui uses an ordinary-hyphen "M-Pesa"', () {
    final hits = ordinaryMpesaHits(_uiSources(), allow: kOrdinaryHyphenAllow);
    expect(hits, isEmpty, reason: 'use the non-breaking hyphen escape in "M-Pesa" in: $hits');
  });

  test('the allow-list is still needed (the Semantics label keeps the ordinary hyphen)', () {
    final all = ordinaryMpesaHits(_uiSources());
    expect(all.length, kOrdinaryHyphenAllow.length, reason: '$all');
  });

  test('the escape is present in the copy files and screens that print the name', () {
    for (final p in [
      'lib/ui/copy/whats_new_pager_copy.dart',
      'lib/ui/copy/data_copy.dart',
      'lib/ui/copy/privacy_copy.dart',
      'lib/ui/screens/onboarding_screen.dart',
      'lib/ui/screens/home/home_screen.dart',
      'lib/ui/screens/add/src_segment.dart',
    ]) {
      expect(File(p).readAsStringSync().contains(r'M\u2011Pesa'), isTrue, reason: p);
    }
  });

  group('negative proof (planted input; the real files are not edited)', () {
    test('an ordinary-hyphen constant in a planted source is reported', () {
      final hits = ordinaryMpesaHits({
        'lib/ui/copy/planted.dart': "const kPlanted = 'Paste an M-Pesa message';\n",
      });
      expect(hits, ['lib/ui/copy/planted.dart:1']);
    });

    test('comments, and the escaped form, are not reported', () {
      final hits = ordinaryMpesaHits({
        'lib/ui/a.dart': "// the M-Pesa tab\nconst a = 'M\\u2011Pesa'; // M-Pesa\n/// M-Pesa doc\n",
      });
      expect(hits, isEmpty);
    });
  });
}
