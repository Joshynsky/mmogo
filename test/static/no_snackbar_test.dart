// 0.2.1 (#37): every toast is the pill toast (lib/ui/widgets/pill_toast.dart), so it follows the theme.
// A Material SnackBar draws light in dark mode, so nothing under lib/ may build one or show one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = RegExp(r'\bSnackBar\s*\(|\bshowSnackBar\s*\(|\bMaterialBanner\s*\(|\bshowMaterialBanner\s*\(');

void main() {
  test('no file under lib/ builds a SnackBar or calls showSnackBar (use PillToast.show)', () {
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//') || l.startsWith('///')) continue;
        if (_banned.hasMatch(lines[i])) hits.add('${e.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty, reason: 'use PillToast.show(...) instead:\n${hits.join('\n')}');
  });

  test('negative control: the scan sees a SnackBar and a showSnackBar call', () {
    expect(_banned.hasMatch('messenger.showSnackBar(const SnackBar(content: Text("x")));'), isTrue);
    expect(_banned.hasMatch('PillToast.show("x");'), isFalse);
  });
}
