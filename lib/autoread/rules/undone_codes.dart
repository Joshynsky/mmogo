/// AUTOREAD RULES undone M-Pesa codes (24 h, cap 100), kept in preferences.
library;

abstract class UndoneCodes {
  Future<void> add(String code, {required DateTime now});

  /// True while the code is unexpired.
  Future<bool> contains(String code, {required DateTime now});
  Future<void> wipe();
}
