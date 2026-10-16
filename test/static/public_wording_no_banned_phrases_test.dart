// B34 / criteria 31 to 35: every public claim matches the truth (the app uses
// the internet ONLY to check for updates). Scans README.md, CHANGELOG.md (all
// versions), docs/index.html, the 0.1.2 release notes and the string literals
// in lib/ for phrases that would deny that, and checks the required sentences
// are present where they must be. 0.1.2 S11c (Q7) extended it in place.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';

/// The one banned list. Lower case; matching is case-insensitive. The promise
/// forms of "safe" / "secure" are listed whole on purpose: the bare words are
/// fine ("safety copy", "somewhere safe", "Is it safe to install?").
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
  // 0.1.2 S11c (C4): a plain word ban, comments in lib are skipped.
  'authentication',
  // 0.1.2 S11c (C4): promise forms only.
  '100% safe',
  'completely safe',
  'totally safe',
  'fully safe',
  '100% secure',
  'completely secure',
  'totally secure',
  'fully secure',
  'bank-grade',
  'military-grade',
  'unhackable',
];

const _releaseNotesPath = '../_pipeline/v0.1.2/phase-7-release/release-notes.md';

String _norm(String path) => path.replaceAll('\\', '/');

/// Drops whole-line `//` and `///` comments (they may quote a banned phrase to
/// forbid it); string literals are what users read.
String _withoutLineComments(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// Banned phrases in [text]. The canonical sentence (exact text, imported)
/// is removed first, in every scanned file: it is the one allowed
/// "No permissions ..." form, and a mangled copy still contains the phrase.
List<String> _hits(String text) {
  final low = text.replaceAll(kPrivacySentenceStandard, '').toLowerCase();
  return [for (final b in _banned) if (low.contains(b)) b];
}

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// The release notes, or null on a clean clone of the app repo (no `_pipeline`).
String? _releaseNotes() {
  final f = File(_releaseNotesPath);
  return f.existsSync() ? _read(_releaseNotesPath) : null;
}

/// The top `## ` section of a CHANGELOG, by position (never compared with the
/// pubspec version, so a version bump does not break this).
String _topSection(String changelog) {
  final lines = changelog.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## '));
  final end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

/// C5: every sentence (split on ". " and line breaks) with "erases" must also
/// say "uninstall". Returns the offending sentences.
List<String> _erasesWithoutUninstall(String text) {
  final bad = <String>[];
  for (final s in text.split(RegExp(r'\. |\n|\\n'))) {
    final low = s.toLowerCase();
    if (low.contains('erases') && !low.contains('uninstall')) bad.add(s.trim());
  }
  return bad;
}

/// Joins adjacent string literals (`'a'\n  'b'`) so a sentence wrapped across
/// literals is one sentence, and drops line comments.
String _joinedLiterals(String src) =>
    _withoutLineComments(src).replaceAll(RegExp(r'''(['"])\s*\n\s*(r?['"])'''), '');

final _eraseWord = RegExp(r'\berase[sd]?\b', caseSensitive: false);

/// U+2011 would break copy-paste and search in public text.
bool _hasNonBreakingHyphen(String text) => text.contains('‑');

Iterable<File> _libFiles() =>
    Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  // ---- scans of the public docs ------------------------------------------
  test('README.md has no banned phrase', () {
    expect(_hits(_read('README.md')), isEmpty);
  });

  test('CHANGELOG.md (all versions) has no banned phrase', () {
    expect(_hits(_read('CHANGELOG.md')), isEmpty);
  });

  test('docs/index.html has no banned phrase', () {
    expect(_hits(_read('docs/index.html')), isEmpty);
  });

  test('the 0.1.2 release notes have no banned phrase', () {
    final rn = _releaseNotes();
    if (rn == null) {
      markTestSkipped('$_releaseNotesPath not found (a clean clone of the app repo has no _pipeline folder)');
      return;
    }
    expect(_hits(rn), isEmpty);
  });

  test('lib/ strings have no banned phrase', () {
    final bad = <String>[];
    for (final f in _libFiles()) {
      final hits = _hits(_withoutLineComments(f.readAsStringSync()));
      if (hits.isNotEmpty) bad.add('${_norm(f.path)}: $hits');
    }
    expect(bad, isEmpty);
  });

  test('C3: "zero permissions" and "not even internet" are in the one list (pinned, no duplicates)', () {
    expect(_banned, containsAll(['zero permissions', 'not even internet', 'no permissions', 'authentication']));
    expect(_banned.toSet(), hasLength(_banned.length));
  });

  // ---- the disclosure sentence and the canonical sentence ----------------
  test('the disclosure sentence is in README, the landing page and the app copy', () {
    const who = 'GitHub sees your IP address and that the request comes from the mmogo app';
    const noData = 'No entries, names or messages are sent';
    for (final path in ['README.md', 'docs/index.html']) {
      final text = _read(path);
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
      for (final f in _libFiles())
        if (f.readAsStringSync().contains('No permissions except internet')) _norm(f.path),
    ];
    expect(defs, hasLength(1));
    expect(defs.single, endsWith('ui/copy/privacy_copy.dart'));
  });

  test('Q7 (a): the canonical sentence is word for word in README, the release notes and CHANGELOG 0.1.2', () {
    expect(_read('README.md'), contains(kPrivacySentenceStandard), reason: 'README.md');
    expect(_topSection(_read('CHANGELOG.md')), contains(kPrivacySentenceStandard), reason: 'CHANGELOG top section');
    final rn = _releaseNotes();
    if (rn == null) {
      markTestSkipped('$_releaseNotesPath not found: release-notes half of rule (a) not checked');
      return;
    }
    expect(rn, contains(kPrivacySentenceStandard), reason: 'release notes');
  });

  test('Q7 (b): the D7 sentence is word for word in CHANGELOG 0.1.2 and the release notes', () {
    expect(_topSection(_read('CHANGELOG.md')), contains(kBackupNotRestorableByOlder), reason: 'CHANGELOG top section');
    final rn = _releaseNotes();
    if (rn == null) {
      markTestSkipped('$_releaseNotesPath not found: release-notes half of rule (b) not checked');
      return;
    }
    expect(rn, contains(kBackupNotRestorableByOlder), reason: 'release notes');
  });

  // ---- C5: "erases" is for uninstalling only ------------------------------
  test('Q7 (c): in the docs every sentence with "erases" says uninstall', () {
    final bad = <String>[];
    for (final path in ['README.md', 'CHANGELOG.md', 'docs/index.html']) {
      for (final s in _erasesWithoutUninstall(_read(path))) {
        bad.add('$path: $s');
      }
    }
    final rn = _releaseNotes();
    if (rn != null) bad.addAll(_erasesWithoutUninstall(rn).map((s) => 'release notes: $s'));
    expect(bad, isEmpty);
  });

  test('Q7 (c): in lib every sentence with "erases" says uninstall (literals joined)', () {
    final bad = <String>[];
    for (final f in _libFiles()) {
      for (final s in _erasesWithoutUninstall(_joinedLiterals(f.readAsStringSync()))) {
        bad.add('${_norm(f.path)}: $s');
      }
    }
    expect(bad, isEmpty);
    // The constants themselves (the wrapped ones are tested as built strings).
    expect(_erasesWithoutUninstall(kUninstallErasesNotice), isEmpty);
    expect(kUninstallErasesNotice.toLowerCase(), contains('uninstall'));
  });

  test('Q7 (c): erase / erases / erased never appears on a Delete data or Reset screen', () {
    final files = [
      for (final f in _libFiles())
        if (_norm(f.path).endsWith('ui/copy/delete_data_copy.dart') || f.readAsStringSync().contains('delete_data_copy.dart')) f,
    ];
    expect(files.map((f) => _norm(f.path)), contains('lib/ui/copy/delete_data_copy.dart'));
    final bad = <String>[];
    for (final f in files) {
      if (_eraseWord.hasMatch(_withoutLineComments(f.readAsStringSync()))) bad.add(_norm(f.path));
    }
    expect(bad, isEmpty);
  });

  // ---- C7: no non-breaking hyphen in public docs --------------------------
  test('U+2011 does not appear in any scanned doc', () {
    final bad = <String>[
      for (final path in ['README.md', 'CHANGELOG.md', 'docs/index.html'])
        if (_hasNonBreakingHyphen(_read(path))) path,
    ];
    final rn = _releaseNotes();
    if (rn != null && _hasNonBreakingHyphen(rn)) bad.add('release notes');
    expect(bad, isEmpty);
  });

  // ---- the rules themselves catch what they should (planted strings) ------
  group('negative proofs on planted text', () {
    test('every banned phrase is caught, in any case', () {
      for (final b in _banned) {
        expect(_hits('Text. ${b.toUpperCase()} here.'), contains(b), reason: b);
      }
    });

    test('the canonical sentence is stripped, but a bare or extended "no permissions" still fails', () {
      expect(_hits('Privacy: $kPrivacySentenceStandard'), isEmpty);
      expect(_hits('$kPrivacySentenceStandard No permissions at all.'), contains('no permissions'));
      expect(_hits('$kPrivacySentenceStandard and no permissions.'), contains('no permissions'));
      // a mangled copy is not stripped
      expect(_hits(kPrivacySentenceStandard.replaceFirst('except', 'besides')), contains('no permissions'));
      expect(_hits(kPrivacySentenceStandard.toUpperCase()), contains('no permissions'));
    });

    test('promise forms fail; the bare words do not', () {
      expect(_hits('It is completely safe.'), contains('completely safe'));
      expect(_hits('Totally Secure storage'), contains('totally secure'));
      expect(_hits('Is it safe to install? Keep a safety copy somewhere safe.'), isEmpty);
      expect(_hits('Your entries are safe on this phone.'), isEmpty);
    });

    test('"erases" without uninstall fails, with uninstall passes, split by sentence and line', () {
      expect(_erasesWithoutUninstall('Delete data erases your entries.'), hasLength(1));
      expect(_erasesWithoutUninstall('Uninstalling mmogo erases your data.'), isEmpty);
      expect(_erasesWithoutUninstall('Uninstall it. Reset erases the rest.'), hasLength(1));
      expect(_erasesWithoutUninstall('Uninstall it.\nReset erases the rest.'), hasLength(1));
      expect(_erasesWithoutUninstall(r'Uninstall it.\nReset ERASES the rest.'), hasLength(1));
    });

    test('wrapped literals are joined before the sentence check; the hard ban finds erase forms', () {
      final joined = _joinedLiterals("const a =\n    'Reset erases '\n    'your data.';\n// erases in a comment\n");
      expect(joined, contains('Reset erases your data.'));
      expect(joined, isNot(contains('comment')));
      expect(_erasesWithoutUninstall(joined), hasLength(1));
      for (final w in ['Erase', 'erases', 'Erased']) {
        expect(_eraseWord.hasMatch('It $w it'), isTrue, reason: w);
      }
      expect(_eraseWord.hasMatch('eraser'), isFalse);
    });

    test('U+2011 is detected', () {
      expect(_hasNonBreakingHyphen('M‑Pesa'), isTrue);
      expect(_hasNonBreakingHyphen('M-Pesa'), isFalse);
    });

    test('top section is taken by position', () {
      expect(_topSection('# C\n\n## 2.0 (x)\nnew\n## 1.0\nold\n'), contains('new'));
      expect(_topSection('# C\n\n## 2.0 (x)\nnew\n## 1.0\nold\n'), isNot(contains('old')));
    });
  });

  test('landing page What is new block is plain static text', () {
    final html = _read('docs/index.html');
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
