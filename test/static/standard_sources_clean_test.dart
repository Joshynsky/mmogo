// The STANDARD source sets must not name auto-read things (Judge AR9).
// Skipped here because manifest_flavor_test.dart already covers it: src/main
// (all files, case-insensitive: RECEIVE_SMS, POST_NOTIFICATIONS, SmsReceiver,
// "autoread", which also covers app/mmogo/autoread and kAutoReadSentinel).
// Added here: src/standard (all files) and lib/ outside lib/autoread/.
// lib/autoread/autoread_feature.dart is inside lib/autoread, so it is out of
// scope by construction. Hook files (kAutoReadHookFiles, from layout_test.dart)
// are exempt from the kAutoReadSentinel rule only, as the hook may use it.
import 'package:flutter_test/flutter_test.dart';

import '../support/static_scan.dart';
import 'layout_test.dart' show kAutoReadHookFiles;

const _words = ['SmsReceiver', 'RECEIVE_SMS', 'POST_NOTIFICATIONS', 'app/mmogo/autoread', 'kAutoReadSentinel'];
final _rules = [for (final w in _words) ScanRule(w, RegExp(RegExp.escape(w)))];
final _noSentinel = _rules.where((r) => r.name != 'kAutoReadSentinel').toList();

void main() {
  test('src/standard names none of the auto-read words', () {
    final files = filesUnder('android/app/src/standard', {'.kt', '.xml', '.java', '.gradle', '.kts'});
    expect(files, isNotEmpty, reason: 'scanner found no files in src/standard');
    final hits = scanFiles(files, _rules);
    expect(hits, isEmpty, reason: 'auto-read words in src/standard (file:line):\n${hits.join('\n')}');
  });

  test('lib/ outside lib/autoread names none of the auto-read words', () {
    final files = filesUnder('lib', {'.dart'}).where((f) => !normPath(f.path).contains('lib/autoread/')).toList();
    expect(files.length, greaterThanOrEqualTo(100), reason: 'scanner found too few files in lib: ${files.length}');
    final hits = <String>[];
    for (final f in files) {
      final p = normPath(f.path);
      final isHook = kAutoReadHookFiles.any((h) => p.endsWith('lib/$h'));
      hits.addAll(scanText(p, f.readAsStringSync(), isHook ? _noSentinel : _rules));
    }
    expect(hits, isEmpty, reason: 'auto-read words outside lib/autoread (file:line):\n${hits.join('\n')}');
  });

  test('the word scan flags each word and passes clean text (self-test)', () {
    for (final w in _words) {
      expect(scanText('x', 'a\nuse $w here\n', _rules).single, startsWith('x:2: $w:'));
    }
    expect(scanText('x', 'class Sms {}\nconst a = 1;\n', _rules), isEmpty);
  });
}
