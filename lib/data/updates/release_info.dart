import 'dart:convert';

import 'untrusted_text.dart';

/// What the app keeps from the GitHub "latest release" answer: a validated
/// tag and sanitised notes. No URL from the response is ever read or kept
/// (criterion 20); every other field is ignored.
class ReleaseInfo {
  const ReleaseInfo({required this.tag, required this.notes});

  /// As sent, validated: `1.2.3` or `v1.2.3`.
  final String tag;

  /// Already passed through [UntrustedText.sanitize]. May be empty.
  final String notes;

  static final _tagPattern = RegExp(r'^v?\d{1,4}\.\d{1,4}\.\d{1,4}$');
  static const _maxTagLength = 32;

  /// The numeric parts of [tag].
  List<int> get versionParts => parseVersion(tag)!;

  /// True only when this release is strictly newer than [installedVersion]
  /// (a name like `0.1.1`). An unparseable [installedVersion] is "not newer".
  bool isNewerThan(String installedVersion) =>
      isNewerVersion(tag, installedVersion);

  /// `null` for anything that is not `v?N.N.N` (1 to 4 digits each; no
  /// pre-release suffix, no fourth part).
  static List<int>? parseVersion(String? tag) {
    if (tag == null || tag.length > _maxTagLength) return null;
    if (!_tagPattern.hasMatch(tag)) return null;
    final bare = tag.startsWith('v') ? tag.substring(1) : tag;
    return bare.split('.').map(int.parse).toList(growable: false);
  }

  /// Numeric tuple compare: is [candidate] strictly newer than [installed]?
  static bool isNewerVersion(String candidate, String installed) {
    final a = parseVersion(candidate);
    final b = parseVersion(installed);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Strict parse of the raw response bytes (malformed UTF-8 is rejected).
  /// Never throws; `null` means "not usable".
  static ReleaseInfo? tryParseBytes(List<int> bytes) {
    try {
      return tryParse(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      return null;
    }
  }

  /// Never throws; `null` means "not usable". Requires a JSON object with a
  /// semver `tag_name`; a draft or prerelease (when the fields are present
  /// they must be the boolean `false`) is rejected.
  static ReleaseInfo? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final tag = json['tag_name'];
      if (tag is! String || parseVersion(tag) == null) return null;
      for (final flag in const ['draft', 'prerelease']) {
        final v = json[flag];
        if (v != null && v != false) return null;
      }
      final rawNotes = json['body'];
      final notes = rawNotes is String ? UntrustedText.sanitize(rawNotes) : '';
      return ReleaseInfo(tag: tag, notes: notes);
    } catch (_) {
      return null;
    }
  }
}
