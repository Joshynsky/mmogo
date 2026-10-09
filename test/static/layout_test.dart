// E7 / E11 / E13 layout checks (mechanical parts only).
//  1. Every `§` marker in lib/ and the Kotlin sources has a row in
//     _pipeline/knowledge/code-map.md, and every code-map row's file path
//     resolves to a real file.
//  2. Only allow-listed hook files import lib/autoread/; nothing in lib/data
//     or lib/domain does.
// Later slices extend [kAutoReadHookFiles] and the code map in the same change.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files outside lib/autoread/ that may import it (E13). Paths are relative to
/// lib/, forward slashes. Empty until the hook slices add their lines.
const kAutoReadHookFiles = <String>[];

const _codeMapPath = '../_pipeline/knowledge/code-map.md';

/// Code-map rows whose section has no `§` marker in code (older rows written
/// before the marker rule). They are checked for file existence only. A NEW
/// row must carry a marker in code, so this list is not to be extended.
const _rowsWithoutCodeMarker = <String>{
  'SCREEN.SETTINGS', 'SCREEN.BACKUP', 'SCREEN.BACKUP.RESTORE', 'SCREEN.BACKUP.AUTO',
  'DATA.AUTO_BACKUP', 'DATA.UPDATES.CLIENT', 'DATA.UPDATES.RELEASE', 'DATA.UPDATES.SERVICE',
  'DATA.BACKUP_COUNTS', 'DATA.BACKUP.LIMITS', 'DATA.BACKUP.CODEC', 'DATA.BACKUP.SETTINGS',
  'DATA.BACKUP.VALIDATOR', 'DATA.BACKUP.REPAIR', 'DATA.BACKUP.RESTORE_TYPES',
  'DATA.BACKUP.RESTORE_PLAN', 'DATA.BACKUP.RESTORE_WRITER', 'DATA.BACKUP.SAFETY_COPY',
  'DATA.DB.MIGRATIONS', 'DATA.PREFS.BACKUP', 'PLATFORM.STORAGE_BRIDGE', 'APP.CONSTANTS',
  'WIDGET.HOLD_STEP', 'SCREEN.MANAGE_CLASS', 'SCREEN.RECENTLY_DELETED', 'SCREEN.PROFILE',
  'SCREEN.ONBOARDING', 'SCREEN.WELCOME', 'SCREEN.UPDATES', 'SCREEN.PRIVACY', 'UI.WHATSNEW',
  'DATA.UPDATES.STARTUP', 'SHELL.BELL', 'SHELL.PRIMARY', 'SHELL.PRIMARY_SCAFFOLD',
  'SHELL.SECONDARY', 'SHELL.ROUTES', 'SHELL.CHROME', 'SHELL.MESSENGER', 'THEME.PALETTE',
  'THEME.SCOPE', 'THEME.APP', 'WIDGET.PERIOD_PILL', 'WIDGET.COACH_TOUR', 'WIDGET.FLAT_PICKER',
  'WIDGET.MPESA_PICKER', 'APP.ENTRY', 'DATA.DB', 'DATA.TRANSACTION', 'DATA.COUNTERPARTY',
  'DATA.CLASSIFICATION', 'DATA.ANALYTICS', 'DATA.HOME', 'DATA.RECENTLY_DELETED', 'DATA.EXPORT',
  'DATA.LOCAL_SUMMARY', 'DATA.SEED', 'DATA.PREFS', 'DOMAIN.PERIOD_MATH', 'DOMAIN.ANALYTICS_PERIOD',
  'DOMAIN.PAID_TO', 'DOMAIN.HOME', 'DOMAIN.PARSING', 'DOMAIN.COUNTERPARTY', 'DOMAIN.CASH',
  'DOMAIN.FORMAT',
  // barrel files: contain only exports, no doc comment marker
  'ANALYTICS.BARREL', 'HOME.BARREL', 'PAIDTO.BARREL',
};

final _markerRe = RegExp(r'§([A-Z][A-Z0-9_]*(?:\.[A-Z0-9_]+)*)');
final _importRe = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

List<File> _sources(String dir, Set<String> exts) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d.listSync(recursive: true).whereType<File>().where((f) => exts.any(f.path.endsWith)).toList();
}

/// Marker -> files that carry it, over lib/ (.dart) and the Android Kotlin sources.
Map<String, Set<String>> _markersInCode() {
  final found = <String, Set<String>>{};
  final files = [..._sources('lib', {'.dart'}), ..._sources('android/app/src', {'.kt'})];
  for (final f in files) {
    final text = f.readAsStringSync(encoding: utf8);
    for (final m in _markerRe.allMatches(text)) {
      found.putIfAbsent(m.group(1)!, () => {}).add(f.path.replaceAll('\\', '/'));
    }
  }
  return found;
}

class _MapRow {
  _MapRow(this.marker, this.fileCell);
  final String marker;
  final String fileCell;
}

List<_MapRow> _codeMapRows() {
  final rows = <_MapRow>[];
  final markerCell = RegExp(r'^[A-Z][A-Z0-9_]*(\.[A-Z0-9_]+)*$');
  for (final line in File(_codeMapPath).readAsLinesSync(encoding: utf8)) {
    if (!line.startsWith('|')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;
    if (!markerCell.hasMatch(cells[1])) continue;
    rows.add(_MapRow(cells[1], cells[2]));
  }
  return rows;
}

/// Every `.dart` path named in a row's file cell must exist under lib/ (full
/// path) or, for a bare file name, somewhere under lib/.
List<String> _missingPaths(_MapRow row, List<String> libFiles) {
  final missing = <String>[];
  for (final m in RegExp(r'[\w./-]+\.dart').allMatches(row.fileCell)) {
    final p = m.group(0)!;
    final ok = p.contains('/') ? libFiles.contains(p) : libFiles.any((f) => f.endsWith('/$p') || f == p);
    if (!ok) missing.add(p);
  }
  return missing;
}

/// Does [spec] (an import string inside [fromFile], relative to lib/) reach lib/autoread/?
bool reachesAutoRead(String fromFile, String spec) {
  if (spec.startsWith('package:mmogo/')) {
    return spec.substring('package:mmogo/'.length).startsWith('autoread/');
  }
  if (spec.startsWith('package:') || spec.startsWith('dart:')) return false;
  final parts = fromFile.split('/')..removeLast();
  for (final seg in spec.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/').startsWith('autoread/');
}

void main() {
  late List<String> libFiles; // relative to lib/, forward slashes
  setUpAll(() {
    libFiles = _sources('lib', {'.dart'})
        .map((f) => f.path.replaceAll('\\', '/'))
        .map((p) => p.substring(p.indexOf('lib/') + 4))
        .toList();
  });

  group('code map', () {
    test('every § marker in lib/ and Kotlin has a code-map row', () {
      final rows = _codeMapRows().map((r) => r.marker).toSet();
      final missing = _markersInCode().keys.where((k) => !rows.contains(k)).toList()..sort();
      expect(missing, isEmpty, reason: 'markers in code with no row in code-map.md: $missing');
    });

    test('every code-map row resolves to a marker in code or is on the known unmarked list', () {
      final inCode = _markersInCode().keys.toSet();
      final stale = _codeMapRows()
          .map((r) => r.marker)
          .where((m) => !inCode.contains(m) && !_rowsWithoutCodeMarker.contains(m))
          .toList()
        ..sort();
      expect(stale, isEmpty, reason: 'code-map rows with no marker in code (and not on the known list): $stale');
    });

    test('every .dart file named in a code-map row exists', () {
      final bad = <String>[];
      for (final r in _codeMapRows()) {
        for (final p in _missingPaths(r, libFiles)) {
          bad.add('${r.marker}: $p');
        }
      }
      expect(bad, isEmpty, reason: 'code-map rows naming files that do not exist:\n${bad.join('\n')}');
    });
  });

  group('lib/autoread import boundary', () {
    test('only lib/autoread itself and the allow-listed hook files import lib/autoread/', () {
      final offenders = <String>[];
      for (final rel in libFiles) {
        if (rel.startsWith('autoread/') || kAutoReadHookFiles.contains(rel)) continue;
        final text = File('lib/$rel').readAsStringSync(encoding: utf8);
        for (final m in _importRe.allMatches(text)) {
          if (reachesAutoRead(rel, m.group(1)!)) offenders.add('$rel imports ${m.group(1)}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no hook file is in lib/data or lib/domain, and every hook file exists', () {
      expect(kAutoReadHookFiles.where((f) => f.startsWith('data/') || f.startsWith('domain/')), isEmpty);
      expect(kAutoReadHookFiles.where((f) => !libFiles.contains(f)), isEmpty);
    });

    test('the matcher catches relative and package imports (self-test)', () {
      expect(reachesAutoRead('ui/screens/x.dart', '../../autoread/autoread_feature.dart'), isTrue);
      expect(reachesAutoRead('main.dart', 'autoread/autoread_feature.dart'), isTrue);
      expect(reachesAutoRead('main.dart', 'package:mmogo/autoread/autoread_feature.dart'), isTrue);
      expect(reachesAutoRead('main.dart', 'package:mmogo/ui/x.dart'), isFalse);
      expect(reachesAutoRead('ui/a/b.dart', '../c.dart'), isFalse);
    });
  });
}
