/// In-memory [UndoneCodes] for tests of later slices. Deterministic: the
/// caller passes the clock.
library;

import 'undone_codes.dart';

class FakeUndoneCodes implements UndoneCodes {
  static const Duration life = Duration(hours: 24);
  final Map<String, DateTime> _expiry = {};

  @override
  Future<void> add(String code, {required DateTime now}) async => _expiry[code] = now.add(life);

  @override
  Future<bool> contains(String code, {required DateTime now}) async {
    final e = _expiry[code];
    return e != null && now.isBefore(e);
  }

  @override
  Future<void> wipe() async => _expiry.clear();
}
