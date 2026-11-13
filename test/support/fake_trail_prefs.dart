// A TrailPrefs in memory with failure switches, for the row 18 tests (auto-read flavor).
import 'package:mmogo/autoread/data/airtime_trail_store.dart';

class FakeTrailPrefs implements TrailPrefs {
  final Map<String, String> map = {};
  bool failRead = false;
  bool failWrite = false;
  final List<String> log = [];

  @override
  Future<String?> read(String key) async {
    log.add('read');
    if (failRead) throw StateError('read failed');
    return map[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    log.add('write');
    if (failWrite) throw StateError('write failed');
    map[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    log.add('remove');
    map.remove(key);
    return true;
  }
}
