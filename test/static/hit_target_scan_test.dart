// S11b item 4 (addendum B7): a tight scan of lib/ui for hit-target constants
// below 44 on something the user taps:
//   (a) `minimumSize: ... Size(w, h)` with w or h below 44 (Size.zero counts);
//   (b) `BoxConstraints(minHeight|minWidth: N)` with N below 44 around an onTap/onPressed;
//   (c) `SizedBox(... height|width: N ...)` with N below 44 that WRAPS a tap
//       (onTap / onPressed / InkWell / GestureDetector / a *Button).
// The scan LISTS what it finds. Every hit is either fixed or on the allow-list
// below with a reason; the test prints the allow-list as a LOG (names + reason)
// and fails if a NEW hit appears or an allow-list line no longer matches.
// It is a heuristic: a false positive goes on the allow-list with its reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class Hit {
  Hit(this.file, this.line, this.kind, this.value, this.snippet);
  final String file;
  final int line;
  final String kind;
  final double value;
  final String snippet;

  /// The stable id of a hit: file + kind + value + a short code snippet.
  String get id => '$file | $kind ${value % 1 == 0 ? value.toInt() : value} | $snippet';
  @override
  String toString() => '$file:$line $kind $value  ${snippet.trim()}';
}

final _tapWords = RegExp(r'onTap:|onPressed:|InkWell\(|GestureDetector\(|InkResponse\(|IconButton\(|TextButton\(|FilledButton\(|OutlinedButton\(|ElevatedButton\(');

/// The text of the call that starts at [open] (index of its `(`), up to the matching `)`.
String _callBody(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return text.substring(open, i + 1);
    }
  }
  return text.substring(open);
}

int _lineOf(String text, int index) => '\n'.allMatches(text.substring(0, index)).length + 1;

/// The scan itself, on a map of path -> source (so a planted source can be fed to it).
List<Hit> scanHitTargets(Map<String, String> sources) {
  final hits = <Hit>[];
  sources.forEach((path, raw) {
    final text = raw.replaceAll('\r\n', '\n');
    // (a) minimumSize
    for (final m in RegExp(r'minimumSize:\s*(const\s+)?(Size\.zero|Size\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)|Size\.square\(\s*([\d.]+)\s*\))').allMatches(text)) {
      final zero = m.group(2) == 'Size.zero';
      final w = zero ? 0.0 : double.parse(m.group(3) ?? m.group(5)!);
      final h = zero ? 0.0 : double.parse(m.group(4) ?? m.group(5)!);
      // A width of 0 means "no minimum width" (the button sizes to its text): only
      // the height is judged then. Size.zero removes the default minimum: flagged.
      final low = zero ? 0.0 : (w == 0 ? h : (w < h ? w : h));
      if (low < 44) hits.add(Hit(path, _lineOf(text, m.start), 'minimumSize', low, m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')));
    }
    // (b) BoxConstraints(minHeight / minWidth) around a tap
    for (final m in RegExp(r'BoxConstraints\(').allMatches(text)) {
      final body = _callBody(text, m.end - 1);
      for (final k in RegExp(r'(minHeight|minWidth):\s*([\d.]+)').allMatches(body)) {
        final v = double.parse(k.group(2)!);
        if (v >= 44) continue;
        // a tap within the 6 lines before or the 20 lines after
        final before = text.substring(0, m.start).split('\n');
        final after = text.substring(m.start).split('\n');
        final lines = [...before.skip((before.length - 7).clamp(0, before.length)), ...after.take(21)].join('\n');
        if (_tapWords.hasMatch(lines)) hits.add(Hit(path, _lineOf(text, m.start), k.group(1)!, v, body.replaceAll(RegExp(r'\s+'), ' ')));
      }
    }
    // (c) SizedBox(height|width: N) wrapping a tap
    for (final m in RegExp(r'SizedBox\(').allMatches(text)) {
      final body = _callBody(text, m.end - 1);
      final props = RegExp(r'^\(\s*(?:key:[^,]+,\s*)?(?:(width|height):\s*([\d.]+),\s*)+', multiLine: false);
      if (!props.hasMatch(body)) continue;
      for (final k in RegExp(r'(?:^|\s|,)(height|width):\s*([\d.]+)\s*,').allMatches(body.substring(0, body.length.clamp(0, 120)))) {
        final v = double.parse(k.group(2)!);
        if (v >= 44 || v == 0) continue;
        if (_tapWords.hasMatch(body)) hits.add(Hit(path, _lineOf(text, m.start), 'SizedBox.${k.group(1)}', v, 'SizedBox(${k.group(1)}: ${k.group(2)}'));
      }
    }
  });
  return hits;
}

Map<String, String> _libUi() {
  final out = <String, String>{};
  for (final e in Directory('lib/ui').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) out[e.path.replaceAll('\\', '/')] = e.readAsStringSync();
  }
  return out;
}

/// Documented exceptions. Key = Hit.id; value = why it stays. Printed as a LOG.
const Map<String, String> kHitTargetAllow = {
  'lib/ui/screens/onboarding_screen.dart | minimumSize 30 | minimumSize: const Size(48, 30)':
      'Skip: 30 px visual pill, tapTargetSize.padded in the same style gives a 48 px hit area (the comment above it says so)',
  'lib/ui/screens/add/type_pills.dart | minWidth 38 | (minWidth: 38)':
      'Add type pill: 38 px pill + 3 px of padding each side INSIDE a TapTarget = a 44 px wide, 44 px high tap box (the comment in type_pills.dart says so; measured in the Add matrix)',
  'lib/ui/widgets/coach_tour.dart | minimumSize 36 | minimumSize: const Size(0, 36)':
      'KNOWN 36 px mock items (coach tour Action / Skip / Back / Next): the Material tap-target default (padded, 48 px) is not switched off here; confirm on the device (TS1 log item)',
};

Map<String, List<Hit>> _byId(List<Hit> hits) {
  final out = <String, List<Hit>>{};
  for (final h in hits) {
    out.putIfAbsent(h.id, () => []).add(h);
  }
  return out;
}

void main() {
  test('every sub-44 hit-target constant in lib/ui is fixed or on the allow-list (LOG below)', () {
    final byId = _byId(scanHitTargets(_libUi()));
    // The LOG: every hit, whether allowed or not. Nothing is hidden.
    for (final e in byId.entries) {
      final allowed = kHitTargetAllow[e.key];
      // ignore: avoid_print
      print('SCAN ${allowed == null ? 'NEW ' : 'LOGGED'} x${e.value.length} ${e.key}${allowed == null ? '' : '  <- $allowed'}');
    }
    final unlisted = byId.keys.where((k) => !kHitTargetAllow.containsKey(k)).toList();
    expect(unlisted, isEmpty, reason: 'new sub-44 hit-target constants: fix them or add them to kHitTargetAllow with a reason');
    final stale = kHitTargetAllow.keys.where((k) => !byId.containsKey(k)).toList();
    expect(stale, isEmpty, reason: 'allow-list lines that no longer match anything: remove them');
  });

  group('negative proof (planted sources; the real files are not edited)', () {
    test('a 30 px minimumSize is found', () {
      final hits = scanHitTargets({
        'lib/ui/planted.dart': 'TextButton(style: TextButton.styleFrom(minimumSize: const Size(30, 30)), onPressed: f, child: t)',
      });
      expect(hits.map((h) => h.kind), ['minimumSize']);
    });

    test('Size.zero is found; Size(0, 44) is not', () {
      expect(scanHitTargets({'a.dart': 'styleFrom(minimumSize: Size.zero)'}).length, 1);
      expect(scanHitTargets({'a.dart': 'styleFrom(minimumSize: const Size(0, 44))'}), isEmpty);
    });

    test('a 30 px SizedBox around a tap is found; around plain text it is not', () {
      expect(
        scanHitTargets({'a.dart': 'SizedBox(\n  height: 30,\n  child: FilledButton(onPressed: f, child: t),\n)'}).map((h) => h.kind),
        ['SizedBox.height'],
      );
      expect(scanHitTargets({'a.dart': 'SizedBox(height: 30, child: Text("x"))'}), isEmpty);
    });

    test('a minHeight below 44 next to an onTap is found', () {
      final hits = scanHitTargets({'a.dart': 'InkWell(onTap: f, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 30), child: c))'});
      expect(hits.map((h) => h.kind), ['minHeight']);
    });
  });
}
