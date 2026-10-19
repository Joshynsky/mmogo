// Shared helpers for the mechanical source scans (auto-read slice ST).
// A scan reads source files as text, runs named regex rules line by line and
// reports "file:line: rule: text" for every hit. No comment or string
// skipping: comments are scanned too, which is stricter and has no false hits
// in the current sources (checked 19-10-2026). If a future comment needs a
// forbidden word, reword the comment.
//
// MMOGO_SCAN_ROOT (environment, default empty) is a folder prefix put in front
// of every scanned directory. It exists only so the negative proof can point
// the scanners at a temporary copy of the sources; normal runs leave it unset.
import 'dart:convert';
import 'dart:io';

class ScanRule {
  const ScanRule(this.name, this.pattern);
  final String name;
  final RegExp pattern;
}

/// Folder prefix for scanned directories ('' normally, 'x/' when the proof sets it).
String scanRoot() {
  final v = Platform.environment['MMOGO_SCAN_ROOT'] ?? '';
  return v.isEmpty ? '' : (v.endsWith('/') ? v : '$v/');
}

String normPath(String p) => p.replaceAll('\\', '/');

/// Files under [dir] (prefixed with [scanRoot]) whose name ends with one of [exts].
List<File> filesUnder(String dir, Set<String> exts) {
  final d = Directory('${scanRoot()}$dir');
  if (!d.existsSync()) return const [];
  return d.listSync(recursive: true).whereType<File>().where((f) => exts.any(f.path.endsWith)).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// One line per hit: `path:line: rule: trimmed source line`.
List<String> scanText(String path, String text, List<ScanRule> rules) {
  final out = <String>[];
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    for (final r in rules) {
      if (r.pattern.hasMatch(lines[i])) out.add('${normPath(path)}:${i + 1}: ${r.name}: ${lines[i].trim()}');
    }
  }
  return out;
}

List<String> scanFiles(Iterable<File> files, List<ScanRule> rules) => [
      for (final f in files) ...scanText(f.path, f.readAsStringSync(encoding: utf8), rules),
    ];

/// Rule for network classes in Dart (used by no_extra_network_test).
final List<ScanRule> kDartSocketRules = [
  ScanRule('network class (Socket/WebSocket/RawSocket/ServerSocket)',
      RegExp(r'\b(Socket|WebSocket|RawSocket|ServerSocket|RawServerSocket|SecureSocket)\b')),
];
