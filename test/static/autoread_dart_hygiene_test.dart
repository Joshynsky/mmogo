// Auto-read static guard (Judge: no network, no logging of message content).
// Every .dart file under lib/autoread/ must reach no
// network class or package, write no log or console output, and launch no URL.
import 'package:flutter_test/flutter_test.dart';

import '../support/static_scan.dart';

final _rules = <ScanRule>[
  ScanRule('network class', RegExp(r'\b(HttpClient|Socket|WebSocket|RawSocket|ServerSocket|RawServerSocket|SecureSocket)\b')),
  ScanRule('network package', RegExp(r'''package:(http|dio|web_socket_channel|url_launcher\w*|firebase_\w+)/''')),
  ScanRule('print(', RegExp(r'(^|[^\w.])print\(')),
  ScanRule('debugPrint(', RegExp(r'\bdebugPrint\(')),
  ScanRule('dart:developer', RegExp(r'dart:developer|\bdeveloper\.\w+\(')),
  ScanRule('log(', RegExp(r'(^|[^\w.])log\(')),
  ScanRule('stdout/stderr', RegExp(r'\b(stdout|stderr)\b')),
  ScanRule('launchUrl', RegExp(r'\blaunchUrl\b')),
  ScanRule('Uri.parse http literal', RegExp(r'''Uri\.parse\(\s*['"]https?''')),
];

void main() {
  test('lib/autoread/*.dart has no network, logging or URL launching', () {
    final files = filesUnder('lib/autoread', {'.dart'});
    expect(files.length, greaterThanOrEqualTo(15), reason: 'scanner found too few files under lib/autoread: ${files.length}');
    final hits = scanFiles(files, _rules);
    expect(hits, isEmpty, reason: 'forbidden code in lib/autoread (file:line):\n${hits.join('\n')}');
  });

  group('detector self-test', () {
    const bad = {
      'network class': 'final s = await Socket.connect(h, 1);',
      'network package': "import 'package:http/http.dart';",
      'print(': "  print('x');",
      'debugPrint(': "debugPrint('x');",
      'dart:developer': "import 'dart:developer' as developer;",
      'log(': "log('x');",
      'stdout/stderr': "stderr.writeln('x');",
      'launchUrl': 'await launchUrl(u);',
      'Uri.parse http literal': "final u = Uri.parse('https://x.test');",
    };
    for (final e in bad.entries) {
      test('flags ${e.key}', () {
        final hits = scanText('lib/autoread/x.dart', 'void f() {}\n${e.value}\n', _rules);
        expect(hits.any((h) => h.contains(': ${e.key}: ') && h.startsWith('lib/autoread/x.dart:2:')), isTrue, reason: '$hits');
      });
    }
    test('passes clean code, including look-alike names', () {
      const clean = "import 'dart:async';\nfinal blog = 1;\nfinal x = footprint(2);\nfinal u = Uri.parse(path);\n"
          'final lookup = catalog(3);\nvoid reprint() {}\n';
      expect(scanText('lib/autoread/ok.dart', clean, _rules), isEmpty);
    });
  });
}
