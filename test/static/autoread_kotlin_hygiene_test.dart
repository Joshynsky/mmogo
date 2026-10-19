// Auto-read static guard for Kotlin: no logging, no console output, no network.
// Scans every .kt under src/autoread, src/main and src/standard.
import 'package:flutter_test/flutter_test.dart';

import '../support/static_scan.dart';

const _dirs = ['android/app/src/autoread', 'android/app/src/main', 'android/app/src/standard'];

final _rules = <ScanRule>[
  ScanRule('android.util.Log', RegExp(r'android\.util\.Log')),
  ScanRule('Log. call', RegExp(r'\bLog\.')),
  ScanRule('println', RegExp(r'\bprintln\b')),
  ScanRule('System.out', RegExp(r'System\.out')),
  ScanRule('printStackTrace', RegExp(r'printStackTrace')),
  ScanRule('java.net', RegExp(r'java\.net')),
  ScanRule('javax.net', RegExp(r'javax\.net')),
  ScanRule('okhttp', RegExp(r'okhttp', caseSensitive: false)),
  ScanRule('HttpURLConnection', RegExp(r'HttpURLConnection')),
  ScanRule('URL(', RegExp(r'\bURL\(')),
  ScanRule('Socket', RegExp(r'Socket')),
];

void main() {
  test('Kotlin sources have no logging, console output or network use', () {
    final files = [for (final d in _dirs) ...filesUnder(d, {'.kt'})];
    expect(files.length, greaterThanOrEqualTo(14), reason: 'scanner found too few .kt files: ${files.length}');
    final names = files.map((f) => normPath(f.path)).toList();
    expect(names.any((p) => p.contains('/src/autoread/') && p.endsWith('SmsReceiver.kt')), isTrue);
    expect(names.any((p) => p.contains('/src/main/') && p.endsWith('MainActivity.kt')), isTrue);
    expect(names.any((p) => p.contains('/src/standard/') && p.endsWith('FeatureHooks.kt')), isTrue);
    final hits = scanFiles(files, _rules);
    expect(hits, isEmpty, reason: 'forbidden Kotlin (file:line):\n${hits.join('\n')}');
  });

  group('detector self-test', () {
    const bad = {
      'android.util.Log': 'import android.util.Log',
      'Log. call': '    Log.d("t", "x")',
      'println': '    println("x")',
      'System.out': '    System.out.print(1)',
      'printStackTrace': '    e.printStackTrace()',
      'java.net': 'import java.net.URI',
      'javax.net': 'import javax.net.ssl.SSLContext',
      'okhttp': 'import okhttp3.OkHttpClient',
      'HttpURLConnection': 'val c: HttpURLConnection? = null',
      'URL(': '    val u = URL("x")',
      'Socket': 'val s = Socket()',
    };
    for (final e in bad.entries) {
      test('flags ${e.key}', () {
        final hits = scanText('A.kt', 'fun f() {}\n${e.value}\n', _rules);
        expect(hits.any((h) => h.contains(': ${e.key}: ') && h.startsWith('A.kt:2:')), isTrue, reason: '$hits');
      });
    }
    test('passes clean code, including look-alike names', () {
      const clean = 'val catalog = 1\nval blog = Dialog.show()\nfun parseUrl(s: String) = s\nval u = MyURL(1)\n';
      expect(scanText('A.kt', clean, _rules), isEmpty);
    });
  });
}
