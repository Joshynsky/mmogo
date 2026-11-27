import 'settings_search_entry.dart';

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

/// Lower-case, accents folded, punctuation turned to single spaces, trimmed.
String normalizeSearchText(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Ranked matches: title starts with the query, then title contains it, then a keyword match.
/// Ties keep Settings order. An empty (or punctuation-only) query finds nothing.
List<SettingsSearchEntry> matchSettingsSearch(String query, List<SettingsSearchEntry> entries) {
  final q = normalizeSearchText(query);
  if (q.isEmpty) return const [];
  final scored = <(int, int, SettingsSearchEntry)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final t = normalizeSearchText(e.title);
    int? rank;
    if (t.startsWith(q)) {
      rank = 0;
    } else if (t.contains(q)) {
      rank = 1;
    } else if (e.keywords.any((k) => normalizeSearchText(k).contains(q))) {
      rank = 2;
    }
    if (rank != null) scored.add((rank, i, e));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored) s.$3];
}
