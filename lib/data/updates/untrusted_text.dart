/// Plain-text sanitiser for text that came over the network (GitHub release
/// notes). The result is only ever shown in a plain `Text`: there is no
/// linkify and no markup, so a URL in the notes stays inert characters.
///
/// Rules (criterion 21): control characters removed (tab becomes a space, a
/// carriage return is dropped, newline is kept), bidi controls, zero-width
/// characters and the Unicode line/paragraph separators removed, at most
/// [maxLines] lines, then at most [maxChars] characters, each cut marked with
/// an ellipsis. Idempotent: `sanitize(sanitize(x)) == sanitize(x)`.
class UntrustedText {
  UntrustedText._();

  static const maxLines = 30;
  static const maxChars = 1500;
  static const _ellipsis = '…';

  static String sanitize(String input) {
    final stripped = _strip(input).trim();
    if (stripped.isEmpty) return '';

    var text = stripped;
    final lines = text.split('\n');
    if (lines.length > maxLines) {
      text = '${lines.take(maxLines).join('\n').trimRight()}$_ellipsis';
    }

    final runes = text.runes.toList();
    if (runes.length > maxChars) {
      text = '${String.fromCharCodes(runes.take(maxChars - 1)).trimRight()}$_ellipsis';
    }
    return text;
  }

  static String _strip(String input) {
    final out = StringBuffer();
    for (final r in input.runes) {
      if (r == 0x0A) {
        out.writeCharCode(r);
      } else if (r == 0x09) {
        out.write(' ');
      } else if (_isDropped(r)) {
        continue;
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  static bool _isDropped(int r) =>
      r < 0x20 || // C0 controls (tab and newline handled by the caller)
      (r >= 0x7F && r <= 0x9F) || // DEL and C1 controls
      r == 0x061C || // Arabic letter mark (bidi)
      (r >= 0x200B && r <= 0x200F) || // zero-width and LRM/RLM
      r == 0x2028 ||
      r == 0x2029 ||
      (r >= 0x202A && r <= 0x202E) || // bidi embeddings and overrides
      (r >= 0x2060 && r <= 0x2064) || // word joiner and invisible operators
      (r >= 0x2066 && r <= 0x2069) || // bidi isolates
      r == 0xFEFF || // BOM / zero-width no-break space
      (r >= 0xE0000 && r <= 0xE007F) || // tag characters (invisible)
      (r >= 0xD800 && r <= 0xDFFF); // lone surrogates
}
