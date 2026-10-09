// E7 source-level twin of tool/check_apk_manifest.ps1: the shared `main`
// Android source set (manifest, Kotlin, Java, res) must carry no SMS or
// notification-listener permission, no SMS receiver and no auto-read name.
// `src/standard` and `src/autoread` are separate source sets and are NOT
// scanned here: only `src/main` is merged into every flavor.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _mainDir = 'android/app/src/main';

const _forbidden = <String>[
  'RECEIVE_SMS',
  'READ_SMS',
  'POST_NOTIFICATIONS',
  'BIND_NOTIFICATION_LISTENER_SERVICE',
  'BROADCAST_SMS',
  'SmsReceiver',
  'autoread', // matched case-insensitively
];

const _binaryExtensions = {'.png', '.webp', '.jpg', '.jpeg', '.gif', '.ttf', '.otf', '.jar', '.so', '.ico'};

void main() {
  test('src/main exists and has the manifest, Kotlin and res to scan', () {
    expect(File('$_mainDir/AndroidManifest.xml').existsSync(), isTrue);
    expect(Directory('$_mainDir/kotlin').existsSync(), isTrue);
    expect(Directory('$_mainDir/res').existsSync(), isTrue);
  });

  test('src/main mentions none of the SMS / notification / autoread names', () {
    final files = Directory(_mainDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !_binaryExtensions.any(f.path.toLowerCase().endsWith))
        .toList();
    expect(files, isNotEmpty);

    final hits = <String>[];
    for (final f in files) {
      final text = f.readAsStringSync(encoding: latin1).toLowerCase();
      for (final word in _forbidden) {
        if (text.contains(word.toLowerCase())) {
          hits.add('${f.path}: $word');
        }
      }
    }
    expect(hits, isEmpty, reason: 'forbidden names in the shared source set:\n${hits.join('\n')}');
  });
}
