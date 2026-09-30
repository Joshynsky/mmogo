// Guards against a text-encoding slip: a source file re-saved in the wrong
// encoding turns a curly apostrophe or a section sign into several garbage
// characters. It compiles fine and only shows up on screen (seen on the Add
// page, 2026-09-29, after a PowerShell rewrite of two files).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no Dart source under lib/ or test/ contains double-encoded (mojibake) text', () {
    // Built from code points so this file never contains the damaged text itself.
    final markers = <String>[
      String.fromCharCodes([0xE2, 0x20AC]), // a mangled dash, quote or ellipsis
      String.fromCharCodes([0xC2, 0xA7]), // a mangled section sign
      String.fromCharCodes([0xC2, 0xB7]), // a mangled middle dot
    ];
    final bad = <String>[];
    for (final root in ['lib', 'test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (markers.any(text.contains)) bad.add(entity.path);
      }
    }
    expect(bad, isEmpty, reason: 'double-encoded text in: $bad');
  });
}
