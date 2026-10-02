import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_validator.dart';
import 'restore_writer.dart' show ExpectedRows;

/// The safety copy could not be written, read back or checked. Replace is
/// then refused before anything in the database changes.
class SafetyCopyError implements Exception {
  const SafetyCopyError(this.what, [this.cause]);
  final String what;
  final Object? cause;

  @override
  String toString() => 'SafetyCopyError($what)';
}

/// The private pre-replace copy (A8): an ordinary backup file in app-private
/// storage (`getApplicationSupportDirectory()/safety/`), not visible to the
/// user and never in a shared folder. Only the NEWEST copy is kept. "Undo
/// replace" restores it.
///
/// Not final: tests substitute a fake that records call order.
class SafetyCopyStore {
  SafetyCopyStore({
    Future<Directory> Function()? baseDir,
    DateTime Function()? now,
  })  : _baseDir = baseDir ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now;

  final Future<Directory> Function() _baseDir;
  final DateTime Function() _now;

  static const String folderName = 'safety';
  static final RegExp namePattern =
      RegExp(r'^mmogo-safety-\d{8}-\d{6}-\d{3}\.json$');

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _baseDir()).path, folderName));
    await dir.create(recursive: true);
    return dir;
  }

  String _name(DateTime t) {
    String n(int v, int w) => v.toString().padLeft(w, '0');
    return 'mmogo-safety-${n(t.year, 4)}${n(t.month, 2)}${n(t.day, 2)}-'
        '${n(t.hour, 2)}${n(t.minute, 2)}${n(t.second, 2)}-${n(t.millisecond, 3)}.json';
  }

  /// Writes [bytes] as the new safety copy and PROVES it is usable before
  /// anything is deleted: read back byte for byte, run through the restore
  /// validator, and its row counts must equal [expect]. Only then are older
  /// copies removed (newest one kept). On any failure the new file is
  /// removed, older copies are left alone, and [SafetyCopyError] is thrown.
  Future<File> write(
    Uint8List bytes, {
    required ExpectedRows expect,
    Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups,
  }) async {
    File? written;
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, _name(_now())));
      final partial = File('${file.path}.partial');
      await partial.writeAsBytes(bytes, flush: true);
      written = await partial.rename(file.path);

      final back = await written.readAsBytes();
      if (!_sameBytes(back, bytes)) throw const SafetyCopyError('read-back differs');
      final v = BackupValidator.validate(back, enabledGroupCodes: enabledGroupCodes);
      if (v.transactions.length != expect.transactions ||
          v.classifications.length != expect.classifications ||
          v.counterpartyMap.length != expect.counterpartyMap) {
        throw const SafetyCopyError('counts differ');
      }
    } catch (e) {
      try {
        if (written != null && await written.exists()) await written.delete();
      } catch (_) {}
      if (e is SafetyCopyError) rethrow;
      throw SafetyCopyError('write or check failed', e);
    }
    await _deleteAllExcept(written);
    return written;
  }

  /// The newest safety copy, or null.
  Future<File?> latest() async {
    final files = await _copies();
    return files.isEmpty ? null : files.last;
  }

  Future<bool> exists() async => (await latest()) != null;

  /// Bytes of the newest safety copy, or null when there is none.
  Future<Uint8List?> readLatest() async {
    final f = await latest();
    return f == null ? null : await f.readAsBytes();
  }

  /// Removes every safety copy (after a successful Undo).
  Future<void> clear() => _deleteAllExcept(null);

  Future<List<File>> _copies() async {
    final dir = await _dir();
    final files = <File>[
      for (final e in dir.listSync())
        if (e is File && namePattern.hasMatch(p.basename(e.path))) e,
    ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  Future<void> _deleteAllExcept(File? keep) async {
    final dir = await _dir();
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      if (keep != null && p.equals(e.path, keep.path)) continue;
      final name = p.basename(e.path);
      if (namePattern.hasMatch(name) || name.endsWith('.json.partial')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
