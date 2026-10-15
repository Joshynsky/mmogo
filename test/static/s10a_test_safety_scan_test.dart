// S10a (addendum G): a test that restores, backs up or touches the safety
// folder must never build the REAL stores. A bare `SafetyCopyStore()` would
// write into the app's real support folder; a bare `AutoBackupService()` would
// talk to the real storage bridge. This scan fails if any test does.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no test constructs SafetyCopyStore() or AutoBackupService() bare', () {
    final bare = RegExp(r'\b(SafetyCopyStore|AutoBackupService)\(\s*\)');
    final hits = <String>[];
    for (final f in Directory('test').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('static/s10a_test_safety_scan_test.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue;
        if (bare.hasMatch(l)) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: 'bare constructions: $hits');
  });

  test('the scan sees a bare construction (self-check of the pattern)', () {
    final bare = RegExp(r'\b(SafetyCopyStore|AutoBackupService)\(\s*\)');
    expect(bare.hasMatch('final s = SafetyCopyStore();'), isTrue);
    expect(bare.hasMatch('AutoBackupService( )'), isTrue);
    expect(bare.hasMatch('SafetyCopyStore(baseDir: () async => tmp)'), isFalse);
    expect(bare.hasMatch('AutoBackupService(bridge: () => b)'), isFalse);
  });
}
