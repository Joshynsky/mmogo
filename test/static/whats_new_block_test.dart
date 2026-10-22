// 0.1.2 S11c (Q5): tool/whats_new_block.dart.
//
// What is proven, said plainly: the 0.1.1 block in docs/index.html was written
// BY HAND (7 items; the 0.1.1 CHANGELOG has 15 bullets and different titles
// and texts). So test (i) proves the RENDERER only: the committed block is
// parsed back into items and rendering them gives the committed block back,
// byte for byte. The CHANGELOG-to-item rule is proven only for 0.1.2 (ii).
// docs/index.html and the CHANGELOG are only read, never written.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/whats_new_block.dart';

String _changelog() => normaliseNewlines(File('CHANGELOG.md').readAsStringSync());

void main() {
  // The landing page's What's new is now a hand-built carousel (the list this renderer
  // produced was replaced), so the renderer is proven on a block it generated itself.
  group('(i) renderer reproduces its own block', () {
    late String generated;
    setUp(() => generated = generateBlock(_changelog())!);

    test('parse the block back into items, render them: byte equal', () {
      final items = parseBlock(generated);
      expect(items, isNotEmpty);
      expect(blockVersion(generated), '0.1.2');
      expect(renderBlock(blockVersion(generated)!, items), generated);
    });

    test('negative: a changed character in a copy is not reproduced', () {
      final items = parseBlock(generated);
      final altered = generated.replaceFirst('<b>', '<b>X');
      expect(renderBlock('0.1.2', items), isNot(altered));
      // and a changed svg stroke width would differ from the render
      final svgAltered = generated.replaceFirst('stroke-width="2.4"', 'stroke-width="2.5"');
      expect(renderBlock('0.1.2', items), isNot(svgAltered));
      // altered text parses to different items, so it cannot equal the original render
      expect(renderBlock('0.1.2', parseBlock(altered)), isNot(renderBlock('0.1.2', items)));
    });

    test('the landing page block is the 0.1.2 carousel: markers once, six cards, no list', () {
      final page = File('docs/index.html').readAsStringSync();
      final block = extractBlock(page)!;
      expect("<h2>What's new in 0.1.2</h2>".allMatches(block), hasLength(1));
      expect('class="slide wn"'.allMatches(block), hasLength(6));
      expect(block, isNot(contains('<li>')));
      expect('<!-- whats-new:start -->'.allMatches(page), hasLength(1));
    });
  });

  group('(ii) 0.1.2 from the CHANGELOG', () {
    test('h2, markers, one li per bullet of the selected sections, no skipped bullets', () {
      final log = _changelog();
      final section = changelogSection(log)!; // newest = first heading
      // Count the bullets of the selected sections independently of the parser.
      var selected = false;
      var bullets = 0;
      for (final l in section) {
        if (l.startsWith('### ')) selected = kBlockSections.contains(l.substring(4).trim());
        if (selected && l.startsWith('- ')) bullets++;
      }
      expect(bullets, greaterThan(0));
      final parsed = parseChangelogItems(section);
      expect(parsed.skipped, isEmpty);
      final block = generateBlock(log)!;
      expect(block, startsWith('<!-- whats-new:start -->\n'));
      expect(block, endsWith('\n<!-- whats-new:end -->'));
      expect('<!-- whats-new:start -->'.allMatches(block), hasLength(1));
      expect('<!-- whats-new:end -->'.allMatches(block), hasLength(1));
      expect(block, contains("<h2>What's new in 0.1.2</h2>"));
      expect('<li>'.allMatches(block), hasLength(bullets));
      expect(parseBlock(block), parsed.items);
      expect(block, isNot(contains('<script')));
    });

    test('default is the first heading; "(date set at release)" and "(2 October 2026)" both give a version', () {
      expect(changelogVersions(_changelog()).first, '0.1.2');
      expect(changelogVersions(_changelog()), containsAllInOrder(['0.1.2', '0.1.1', '0.1.0']));
      expect(generateBlock('# C\n\n## 9.9.9 (any text, here)\n\n### Added\n- **A.** b\n'), contains('What\'s new in 9.9.9'));
      expect(generateBlock('# C\n\n## 9.9.9\n\n### Added\n- **A.** b\n'), contains('What\'s new in 9.9.9'));
      expect(generateBlock(_changelog(), '0.0.0'), isNull);
    });

    test('Fixed is not in the block; the section list is a constant', () {
      expect(kBlockSections, ['Added', 'Changed', 'Good to know']);
      final log = _changelog();
      final fixedTitle = RegExp(r'### Fixed\n- \*\*(.+?)\*\*').firstMatch(log.substring(0, log.indexOf('## 0.1.1')))![1]!;
      expect(generateBlock(log)!, isNot(contains('<b>${fixedTitle.replaceAll(RegExp(r'\.$'), '')}</b>')));
      final withFixed = parseChangelogItems(changelogSection(log)!, sections: [...kBlockSections, 'Fixed']).items;
      expect(withFixed.length, parseChangelogItems(changelogSection(log)!).items.length + 1);
    });

    test('ASCII: the output holds no non-ASCII character the section itself does not hold (no U+2011)', () {
      final log = _changelog();
      final block = generateBlock(log)!;
      final inSection = changelogSection(log)!.join('\n').runes.where((r) => r > 127).toSet();
      expect(block.runes.where((r) => r > 127).toSet().difference(inSection), isEmpty);
      expect(block, isNot(contains('‑')));
      expect(block.contains('M-Pesa'), isTrue);
    });
  });

  group('(iii) escaping and markdown, pinned', () {
    const md = '''# C

## 1.2.3 (date set at release)

### Added
- **Tom & Jerry <b>.** Say "hi" & don't <script>x</script> use `code` and **more** > 3.
- no bold lead here
- **Wrapped.** first line
  second line

### Fixed
- **Not in the block.** no
''';

    test('& < > escaped; quotes and apostrophes stay raw; marks removed', () {
      final p = parseChangelogItems(changelogSection(md)!);
      expect(p.items.first.title, 'Tom & Jerry <b>');
      final block = generateBlock(md)!;
      expect(block, contains('<b>Tom &amp; Jerry &lt;b&gt;</b>'));
      expect(block, contains('Say "hi" &amp; don\'t &lt;script&gt;x&lt;/script&gt; use code and more &gt; 3.'));
      expect(block, isNot(contains('<script')));
      expect(block, isNot(contains('`')));
      expect(block, isNot(contains('**')));
      expect(block, contains('<p class="eyebrow">What\'s new</p>'));
    });

    test('a bullet without a bold lead is skipped and reported; wrapped bullets join', () {
      final p = parseChangelogItems(changelogSection(md)!);
      expect(p.skipped, ['no bold lead here']);
      expect(p.items.map((i) => i.title), ['Tom & Jerry <b>', 'Wrapped']);
      expect(p.items.last.text, 'first line second line');
    });

    test('negative: without escaping the planted <script> would show; the pure function escapes it', () {
      final planted = generateBlock('## 1.0.0\n\n### Added\n- **T.** <script>alert(1)</script>\n')!;
      expect(planted, isNot(contains('<script')));
      expect(planted, contains('&lt;script&gt;'));
      // Round trip through the block parser restores the characters.
      expect(parseBlock(planted).single.text, '<script>alert(1)</script>');
      // escapeHtml is not a no-op and orders & first (no double escaping of the entities it adds).
      expect(escapeHtml('<&>'), '&lt;&amp;&gt;');
      expect(unescapeHtml(escapeHtml('a&lt;b')), 'a&lt;b');
    });
  });
}
