/// §AUTOREAD.FLAG — the compile-time switch for the optional auto-read
/// feature. False in the standard build; the autoread build sets it with
/// `--dart-define=MMOGO_AUTOREAD=true` (tool/build_apk.ps1 sets flavor and
/// define together). Nothing else lives here.
const bool kAutoReadCompiled = bool.fromEnvironment('MMOGO_AUTOREAD');
