import '../../../data/updates/untrusted_text.dart';

/// Release notes as shown on screen: sanitised again (controls, bidi, 30
/// lines, 1,500 characters), then a light Markdown strip so GitHub notes read
/// as plain words: a leading `#` heading marker, `**` and backticks go.
/// Everything else stays as characters, links included (they are never
/// tappable). Idempotent.
String plainReleaseNotes(String raw) {
  final lines = UntrustedText.sanitize(raw).split('\n');
  final heading = RegExp(r'^\s{0,3}#{1,6}\s+');
  return lines
      .map((l) => l.replaceFirst(heading, '').replaceAll('**', '').replaceAll('`', ''))
      .join('\n');
}
