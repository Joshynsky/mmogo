// 0.1.3 SEC-03: the export temp files (ours and the share plugin's copy) are removed; nothing else is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/export_temp_sweep.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory cache;

  setUp(() => cache = Directory.systemTemp.createTempSync('mmogo-sweep-test'));
  tearDown(() => cache.deleteSync(recursive: true));

  File touch(String rel) => File(p.join(cache.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync('name,phone\n');

  test('removes export files in the cache folder and in share_plus, and leaves everything else', () async {
    final a = touch('mmogo-export-1793254942365.csv');
    final b = touch('share_plus/mmogo-export-1793254942365.csv');
    final c = touch('share_plus/mmogo-export-1.csv');
    final keepOther = touch('other.csv');
    final keepPdf = touch('share_plus/keep.pdf');
    final keepBackup = touch('mmogo-backup-20261029-094000.json');

    expect(await sweepExportTemp(cache), 3);

    expect([a, b, c].any((f) => f.existsSync()), isFalse);
    expect([keepOther, keepPdf, keepBackup].every((f) => f.existsSync()), isTrue);
  });

  test('a missing folder, an empty folder and a second sweep are all fine', () async {
    expect(await sweepExportTemp(Directory(p.join(cache.path, 'nope'))), 0);
    expect(await sweepExportTemp(cache), 0);
    touch('mmogo-export-2.csv');
    expect(await sweepExportTemp(cache), 1);
    expect(await sweepExportTemp(cache), 0);
  });

  test('a folder that looks like an export file is not touched', () async {
    final d = Directory(p.join(cache.path, 'mmogo-export-3.csv'))..createSync();
    expect(await sweepExportTemp(cache), 0);
    expect(d.existsSync(), isTrue);
  });
}
