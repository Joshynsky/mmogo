// B34 / criteria 31 to 35: every public claim matches the 0.1.1 truth (the app
// uses the internet ONLY to check for updates). Scans README.md, docs/index.html
// and the string literals in lib/ for phrases that would deny that, and checks
// the one disclosure sentence is present where it must be.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';

const _banned = <String>[
  'nothing is sent',
  'no permissions',
  'no permission at all',
  '0 permissions',
  'zero permissions',
  'no internet',
  'not even internet',
  'never connects',
  'works offline',
  'free, offline',
];

String _norm(String path) => path.replaceAll('\\', '/');

/// Drops whole-line `//` and `///` comments (they may quote a banned phrase to
/// forbid it); string literals are what users read.
String _withoutLineComments(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

List<String> _hits(String text) {
  final low = text.toLowerCase();
  return [for (final b in _banned) if (low.contains(b)) b];
}

void main() {
  test('README.md has no banned phrase', () {
    expect(_hits(File('README.md').readAsStringSync()), isEmpty);
  });

  test('docs/index.html has no banned phrase', () {
    expect(_hits(File('docs/index.html').readAsStringSync()), isEmpty);
  });

  test('lib/ strings have no banned phrase', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      var src = _withoutLineComments(f.readAsStringSync());
      // 0.1.2 (C12, E8): the canonical sentence is the ONE allowed "No permissions ..." form, and
      // only as the constant in privacy_copy.dart.
      if (_norm(f.path).endsWith('ui/copy/privacy_copy.dart')) src = src.replaceAll(kPrivacySentenceStandard, '');
      final hits = _hits(src);
      if (hits.isNotEmpty) bad.add('${_norm(f.path)}: $hits');
    }
    expect(bad, isEmpty);
  });

  test('the disclosure sentence is in README, the landing page and the app copy', () {
    const who = 'GitHub sees your IP address and that the request comes from the mmogo app';
    const noData = 'No entries, names or messages are sent';
    for (final path in ['README.md', 'docs/index.html']) {
      final text = File(path).readAsStringSync();
      expect(text, contains(who), reason: path);
      expect(text, contains(noData), reason: path);
    }
    // The app copy is wrapped across string literals, so check the constant.
    expect(kNetworkSentence, contains(who));
    expect(kNetworkSentence, contains(noData));
  });

  test('S1: the canonical privacy sentence is exact and defined in exactly one place in lib/', () {
    expect(kPrivacySentenceStandard, 'No permissions except internet, used only to check for updates (switchable off).');
    final defs = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('No permissions except internet')) _norm(f.path),
    ];
    expect(defs, hasLength(1));
    expect(defs.single, endsWith('ui/copy/privacy_copy.dart'));
  });

  test('landing page What is new block is plain static text', () {
    final html = File('docs/index.html').readAsStringSync();
    final start = html.indexOf('<!-- whats-new:start -->');
    final end = html.indexOf('<!-- whats-new:end -->');
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    final block = html.substring(start, end);
    expect(block, isNot(contains('<script')));
    expect(block, isNot(contains('fetch(')));
    expect(block, isNot(contains('api.github.com')));
  });
}
