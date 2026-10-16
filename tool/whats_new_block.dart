// What's-new block generator for the landing page (0.1.2 S11c, Q5).
//
//   dart run tool/whats_new_block.dart [version]
//   dart tool/whats_new_block.dart [version]     (same; `dart run` prints a
//   "Running build hooks..." line on stdout first, this form does not)
//
// Reads CHANGELOG.md, takes the section of the given version (default: the
// first `## ` heading, the newest) and prints the landing "What's new" block
// between its two markers, in exactly the markup of the block in
// docs/index.html. It never writes a file: the landing refresh (Q6) pastes it.
//
// Plain Dart: no flutter and no mmogo import, so it runs with `dart run`.
//
// TWO PARTS
//   PARSER   [parseChangelogItems]: CHANGELOG section -> items.
//   RENDERER [renderBlock]: items + version -> the exact markup.
//
// MAPPING RULE (parser)
//   * The section's `### ` headings listed in [kBlockSections] feed the block;
//     other headings (today: Fixed) are skipped. The list is a constant so
//     the PM can overrule it at Q6.
//   * A bullet (`- `, continuation lines indented) becomes one item when it
//     starts with `**bold**`: title = the bold text without its trailing full
//     stop, text = the rest of the bullet.
//   * A bullet without a bold lead is SKIPPED and reported in
//     [ParsedItems.skipped] (the tool prints them on stderr).
//   * Inline `code` and other `**x**` inside the text become plain text
//     without the marks.
//   * Text is HTML-escaped: & < > only. Quotes and apostrophes stay raw (they
//     only ever appear in element text).
//
// WHAT IS PROVEN (test/static/whats_new_block_test.dart)
//   The 0.1.1 block in docs/index.html was WRITTEN BY HAND: its titles and
//   texts differ from the 0.1.1 CHANGELOG bullets (7 items from 15 bullets).
//   No rule gives that text from the CHANGELOG, so it is NOT reproduced. What
//   is proven on the real file is the RENDERER: the committed block is parsed
//   back into items ([parseBlock]) and rendering them gives it back byte for
//   byte (markup, spacing, svg). The CHANGELOG-to-item rule is proven only on
//   the 0.1.2 section, in the test.

import 'dart:io';

/// The `### ` sections whose bullets become items (PM may change at Q6).
const kBlockSections = <String>['Added', 'Changed', 'Good to know'];

const kBlockStart = '<!-- whats-new:start -->';
const kBlockEnd = '<!-- whats-new:end -->';

const _svg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" '
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    '<circle cx="12" cy="12" r="10"/><path d="M7.5 12.5l3 3 6-6.5"/></svg>';

class BlockItem {
  const BlockItem(this.title, this.text);
  final String title;
  final String text;

  @override
  bool operator ==(Object other) => other is BlockItem && other.title == title && other.text == text;

  @override
  int get hashCode => Object.hash(title, text);

  @override
  String toString() => 'BlockItem($title | $text)';
}

class ParsedItems {
  const ParsedItems(this.items, this.skipped);
  final List<BlockItem> items;

  /// Bullets of a selected section that have no bold lead (not in the block).
  final List<String> skipped;
}

/// `&` `<` `>` only (quotes and apostrophes stay raw: element text only).
String escapeHtml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String unescapeHtml(String s) => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');

String _plain(String s) => s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!).replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!);

/// Normalises line endings (the working tree may be CRLF).
String normaliseNewlines(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

final _versionHeading = RegExp(r'^## (\S+)(?:\s*\((.*)\))?\s*$');

/// The version names in order of appearance (`## 0.1.2 (anything)` -> 0.1.2).
List<String> changelogVersions(String changelog) => [
      for (final l in normaliseNewlines(changelog).split('\n'))
        if (_versionHeading.firstMatch(l) case final m?) m[1]!,
    ];

/// The lines of the section of [version] (default: the first `## ` heading), or
/// null when there is no such version.
List<String>? changelogSection(String changelog, [String? version]) {
  final lines = normaliseNewlines(changelog).split('\n');
  final out = <String>[];
  var inside = false;
  for (final l in lines) {
    final m = _versionHeading.firstMatch(l);
    if (m != null) {
      if (inside) break;
      if (version == null || m[1] == version) {
        inside = true;
        continue;
      }
    } else if (l.startsWith('## ') && inside) {
      break;
    }
    if (inside) out.add(l);
  }
  return inside ? out : null;
}

/// PARSER: a section (from [changelogSection]) -> items.
ParsedItems parseChangelogItems(List<String> section, {List<String> sections = kBlockSections}) {
  final items = <BlockItem>[];
  final skipped = <String>[];
  var selected = false;
  final bullets = <String>[];
  void flush() {
    if (bullets.isEmpty) return;
    final raw = bullets.join(' ').trim();
    bullets.clear();
    final m = RegExp(r'^\*\*(.+?)\*\*(.*)$').firstMatch(raw);
    if (m == null) {
      skipped.add(raw);
      return;
    }
    var title = _plain(m[1]!.trim());
    if (title.endsWith('.')) title = title.substring(0, title.length - 1);
    items.add(BlockItem(title, _plain(m[2]!.trim())));
  }

  for (final l in section) {
    if (l.startsWith('### ')) {
      flush();
      selected = sections.contains(l.substring(4).trim());
      continue;
    }
    if (!selected) continue;
    if (l.startsWith('- ')) {
      flush();
      bullets.add(l.substring(2));
    } else if (bullets.isNotEmpty && l.startsWith('  ')) {
      bullets.add(l.trim());
    } else {
      flush();
    }
  }
  flush();
  return ParsedItems(items, skipped);
}

/// RENDERER: items + version -> the block, markers included, `\n` newlines,
/// no trailing newline. The markup is lines 318-334 of docs/index.html.
String renderBlock(String version, List<BlockItem> items) {
  final b = StringBuffer()
    ..write('$kBlockStart\n')
    ..write('  <section id="whats-new" style="padding-top:0">\n')
    ..write('    <div class="wrap">\n')
    ..write('      <p class="eyebrow">What\'s new</p>\n')
    ..write('      <h2>What\'s new in ${escapeHtml(version)}</h2>\n')
    ..write('      <ul class="checks">\n');
  for (final i in items) {
    b.write('        <li>$_svg<div><b>${escapeHtml(i.title)}</b><span>${escapeHtml(i.text)}</span></div></li>\n');
  }
  b
    ..write('      </ul>\n')
    ..write('    </div>\n')
    ..write('  </section>\n')
    ..write(kBlockEnd);
  return b.toString();
}

/// The block (markers included) found in a landing page, or null.
String? extractBlock(String html) {
  final h = normaliseNewlines(html);
  final s = h.indexOf(kBlockStart);
  final e = h.indexOf(kBlockEnd);
  if (s < 0 || e < s) return null;
  return h.substring(s, e + kBlockEnd.length);
}

/// The version in the block's h2, or null.
String? blockVersion(String block) {
  final m = RegExp(r"<h2>What's new in (.*?)</h2>").firstMatch(block);
  return m == null ? null : unescapeHtml(m[1]!);
}

/// A block back into items (title from `<b>`, text from `<span>`).
List<BlockItem> parseBlock(String block) => [
      for (final m in RegExp(r'<li><svg[^>]*>.*?</svg><div><b>(.*?)</b><span>(.*?)</span></div></li>').allMatches(block))
        BlockItem(unescapeHtml(m[1]!), unescapeHtml(m[2]!)),
    ];

/// The whole job as a pure function: CHANGELOG text + version -> block, or
/// null when the version is not in the CHANGELOG.
String? generateBlock(String changelog, [String? version]) {
  final section = changelogSection(changelog, version);
  if (section == null) return null;
  final v = version ?? changelogVersions(changelog).first;
  return renderBlock(v, parseChangelogItems(section).items);
}

void main(List<String> args) {
  final file = File('CHANGELOG.md');
  if (!file.existsSync()) {
    stderr.writeln('CHANGELOG.md not found: run from the app folder.');
    exit(2);
  }
  final text = file.readAsStringSync();
  final version = args.isEmpty ? null : args.first;
  final section = changelogSection(text, version);
  if (section == null) {
    stderr.writeln('No section for version ${version ?? '(newest)'} in CHANGELOG.md.');
    exit(1);
  }
  final v = version ?? changelogVersions(text).first;
  final parsed = parseChangelogItems(section);
  for (final s in parsed.skipped) {
    stderr.writeln('Skipped (no bold lead): $s');
  }
  stdout.writeln(renderBlock(v, parsed.items));
}
