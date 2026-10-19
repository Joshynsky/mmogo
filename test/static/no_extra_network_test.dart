// B6 / criterion 14: the app has ONE network site. `HttpClient(` may appear
// only in lib/data/updates/update_check_client.dart (added by B25; until then
// this passes with no matches), and there is no package:http or url_launcher.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/static_scan.dart';

Iterable<File> _dartFiles(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

String _norm(String path) => path.replaceAll('\\', '/');

void main() {
  test('HttpClient( appears only in update_check_client.dart', () {
    final hits = <String>[];
    for (final f in _dartFiles('lib')) {
      if (RegExp(r'\bHttpClient\s*\(').hasMatch(f.readAsStringSync())) hits.add(_norm(f.path));
    }
    expect(hits.where((p) => !p.endsWith('lib/data/updates/update_check_client.dart')), isEmpty);
    expect(hits.length, lessThanOrEqualTo(1));
  });

  test('no package:http and no url_launcher in lib/ or direct dependencies', () {
    for (final f in _dartFiles('lib')) {
      final src = f.readAsStringSync();
      expect(src, isNot(contains('package:http/')), reason: _norm(f.path));
      expect(src, isNot(contains('package:url_launcher')), reason: _norm(f.path));
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s{2}http\s*:', multiLine: true).hasMatch(pubspec), isFalse);
    expect(RegExp(r'^\s{2}url_launcher\w*\s*:', multiLine: true).hasMatch(pubspec), isFalse);
  });

  // Added 19-10-2026 (auto-read slice ST): the old checks only look for HttpClient(.
  // No raw socket or web socket class may appear anywhere in lib/ (no exemption).
  test('no Socket, WebSocket, RawSocket or ServerSocket anywhere in lib/', () {
    final files = filesUnder('lib', {'.dart'});
    expect(files.length, greaterThanOrEqualTo(200), reason: 'scanner found too few files in lib: ${files.length}');
    final hits = scanFiles(files, kDartSocketRules);
    expect(hits, isEmpty, reason: 'socket classes in lib (file:line):\n${hits.join('\n')}');
  });

  test('the socket detector flags each class and passes clean code (self-test)', () {
    for (final c in ['Socket', 'WebSocket', 'RawSocket', 'ServerSocket']) {
      expect(scanText('lib/x.dart', 'a\nfinal s = await $c.connect(h, 1);\n', kDartSocketRules), hasLength(1), reason: c);
    }
    expect(scanText('lib/x.dart', 'final blocket = 1;\nclass SocketLess {}\n', kDartSocketRules), isEmpty);
  });
}
