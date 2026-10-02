// In-memory SafetyCopyStore for restore tests: records every call in a shared
// [events] list (to prove call order), can fail on write or on read-back.
import 'dart:io';
import 'dart:typed_data';

import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';

class FakeSafetyCopyStore implements SafetyCopyStore {
  FakeSafetyCopyStore(this.events, {this.failWrite = false, this.unreadable = false});

  final List<String> events;
  bool failWrite;

  /// Simulates a copy that was written but reads back corrupt: the real
  /// store's read-back check would refuse it, so this fake throws too.
  bool unreadable;

  Uint8List? bytes;

  @override
  Future<File> write(
    Uint8List data, {
    required ExpectedRows expect,
    Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups,
  }) async {
    events.add('safety.write');
    if (failWrite) throw const SafetyCopyError('disk full');
    final back = unreadable ? Uint8List.fromList(data.sublist(0, data.length ~/ 2)) : data;
    try {
      final v = BackupValidator.validate(back, enabledGroupCodes: enabledGroupCodes);
      if (v.transactions.length != expect.transactions) {
        throw const SafetyCopyError('counts differ');
      }
    } on RestoreRejected catch (e) {
      throw SafetyCopyError('read-back invalid', e);
    }
    bytes = Uint8List.fromList(data);
    return File('fake-safety.json');
  }

  @override
  Future<bool> exists() async => bytes != null;

  @override
  Future<File?> latest() async => bytes == null ? null : File('fake-safety.json');

  @override
  Future<Uint8List?> readLatest() async {
    events.add('safety.read');
    return bytes;
  }

  @override
  Future<void> clear() async {
    events.add('safety.clear');
    bytes = null;
  }
}

/// BackupSettings that records when it is called (and, through [probe], what
/// the database looked like at that moment).
class RecordingSettings extends BackupSettings {
  RecordingSettings(this.events, {this.probe});

  final List<String> events;
  final Future<void> Function()? probe;
  final List<bool> onlyIfUnsetCalls = [];

  @override
  Future<SettingsApplyResult> applyAfterCommit(
    Map<String, Object?> settings, {
    bool onlyIfUnset = false,
  }) async {
    events.add('settings.apply');
    onlyIfUnsetCalls.add(onlyIfUnset);
    if (probe != null) await probe!();
    return SettingsApplyResult(ok: true, applied: settings.keys.toList());
  }
}
