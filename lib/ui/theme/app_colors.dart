import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette_scope.dart';

/// Design tokens from the design system's phone-frame-shell/topbar/nav
/// conventions (earlier prototype), reproduced here as real Flutter color
/// constants — not copied prototype code, just the same agreed-upon values so
/// the real build reads visually consistent with the validated prototype.
///
/// `muted`/`border`/`iconBtnBg` in particular carry forward the
/// Accessibility/User Researcher WCAG 1.4.3 contrast fix (`#63666e`, not the
/// original `#7a7f87`/`#9096a0`).
class AppColors {
  AppColors._();

  static const primary = Color(0xFF00A651);
  static const primaryDark = Color(0xFF00822E);
  static const bg = Color(0xFFF5F7FA);
  static const card = Colors.white;
  static const text = Color(0xFF1B1E22);
  static const muted = Color(0xFF63666E);
  static const border = Color(0xFFE1E5EA);
  static const iconBtnBg = Color(0xFFEEF1F4);

  /// Fixed per-`source_type` colors for the donut+legend component
  /// — the same four colors
  /// reused everywhere a source_type breakdown appears (Home now;
  /// Parties/Analytics later), never invented per-screen.
  static const sourceSendMoney = primary; // #00A651
  static const sourcePaybill = Color(0xFF3D7FE0);
  static const sourceBuyGoods = Color(0xFF8B5CF6);
  static const sourceCash = Color(0xFFF5A623);

  // --- Ocean & Sun: app-wide colours that don't change with light/dark
  // (PM direct decision, 2026-09-24: Ocean & Sun, with dark mode). The per-theme tokens live in [AppPalette]. ---

  /// Sun: warm accent (cash, highlights), same in light and dark. Only with
  /// dark text (8.95:1 with #13262E). Not used by onboarding yet.
  static const sun = Color(0xFFFFB703);

  // The transaction-type chart colours are per-theme tokens now
  // ([AppPalette.typeSendMoney] etc., T20): one source, light + dark.
}

/// The Ocean & Sun palette as a light/dark pair of token sets (PM direct
/// decision, 2026-09-24; values are the approved mock v3's own tokens
/// for the light and dark phone).
///
/// Resolve it with [AppPalette.of], which follows the PHONE's light/dark
/// setting (`MediaQuery.platformBrightnessOf`), not the app's [ThemeData]:
/// the app's ThemeData stays pinned to light so screens that haven't been
/// reworked yet never half-darken. Welcome, onboarding and Home (T20) call
/// [AppPalette.of]; each page adopts it as the page-by-page rework reaches
/// it. The primary chrome uses [AppPalette.light] on the pinned-light pages
/// (see `PrimaryScaffold.followPhoneTheme`).
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.deep,
    required this.backBg,
    required this.backInk,
    required this.tint,
    required this.tintInk,
    required this.brightPill,
    required this.dotIdle,
    required this.ink,
    required this.softInk,
    required this.mutedInk,
    required this.background,
    required this.surface,
    required this.textCard,
    required this.line,
    required this.frameLine,
    required this.skipBg,
    required this.skipInk,
    required this.sun,
    required this.card,
    required this.track,
    required this.diffUp,
    required this.diffDown,
    required this.typeSendMoney,
    required this.typePaybill,
    required this.typeBuyGoods,
    required this.typeCash,
    required this.bar,
    required this.barOn,
    required this.highlight,
    required this.toastAction,
    required this.onDelete,
    required this.onTypeColor,
  });

  /// Which theme this token set is for.
  final Brightness brightness;

  /// Primary buttons, the focused input border (mock `--jade`).
  final Color primary;

  /// Text/icons on [primary] (mock `--btn-ink`).
  final Color onPrimary;

  /// Strong text, focus rings (mock `--jade-deep`).
  final Color deep;

  /// Round Back button fill (mock `--back-bg`).
  final Color backBg;

  /// Arrow on [backBg] (mock `--back-ink`).
  final Color backInk;

  /// Image areas, the Welcome logo placeholder (mock `--jade-tint`).
  final Color tint;

  /// Text on [tint]: the Welcome word, the parse-strip captions and arrows
  /// (mock `--tint-ink`).
  final Color tintInk;

  /// Active progress pill; decorative only, never behind text (mock `--dot`).
  final Color brightPill;

  /// Inactive progress dots (mock `--dot-idle`).
  final Color dotIdle;

  /// Body text (mock `--ink`).
  final Color ink;

  /// Secondary text on [textCard] (mock `--soft-ink`).
  final Color softInk;

  /// Hints, "Tap to continue" (mock `--muted-ink`).
  final Color mutedInk;

  /// Page background (mock `--mist`).
  final Color background;

  /// Welcome background, strip frames, inputs (mock `--surface`).
  final Color surface;

  /// Onboarding's short-text card (mock `--card`).
  final Color textCard;

  /// Input border (mock `--line`).
  final Color line;

  /// Parse-strip frame border (mock `--frame-line`).
  final Color frameLine;

  /// Skip pill fill, translucent over the image (mock `--skip-bg`).
  final Color skipBg;

  /// Skip label (mock `--skip-ink`).
  final Color skipInk;

  /// Warm accent, same in both themes ([AppColors.sun]).
  final Color sun;

  // --- Home (T20; Home colours mock v4 `.phone` / `.phone.dark`) and the
  // shared primary chrome. ---

  /// Cards on Home, the bottom nav, the Profile button (mock `--surface`).
  final Color card;

  /// Empty part of a bar (mock `--track`).
  final Color track;

  /// ▲ spending rose (mock `--up`; > 5.6:1 on [card]).
  final Color diffUp;

  /// ▼ spending fell (mock `--down`; the same Ocean as [primary]).
  final Color diffDown;

  /// Chart colours per transaction type (mock `--c1`..`--c4`; PM-approved
  /// nudge of the Ocean & Sun type colours). Each bar is >= 3:1 on [card].
  final Color typeSendMoney;
  final Color typePaybill;
  final Color typeBuyGoods;
  final Color typeCash;

  // --- Analytics (T21; Analytics mock v4 view B `.phone` / `.phone.dark`). ---

  /// Muted bar fill (mock `--bar`); also the toast's Undo on dark.
  final Color bar;

  /// Active bar fill (mock `--bar-on`).
  final Color barOn;

  /// A row lit up after the Home hand-off, an edit or an Undo (mock `--hl`).
  final Color highlight;

  /// The toast's action label (mock `.btoast button`: #8FD3E6 on light,
  /// `--bar` on dark), on an [ink] toast.
  final Color toastAction;

  /// Text/icon on the [diffUp]-red Delete swipe action (mock `.bact .del`:
  /// white on light, #2A0E0C on dark).
  final Color onDelete;

  /// Initials on a type-coloured avatar (mock `.bparty .av`: #fff on light;
  /// Ocean dark uses a dark ink instead, T26, so it clears 3:1 on every type
  /// colour — see the new palettes' own dark `onTypeColor`).
  final Color onTypeColor;

  /// The chart colour for a `source_type` code ('SEND_MONEY', 'PAYBILL',
  /// 'BUY_GOODS', 'CASH'); [mutedInk] for anything else.
  Color typeColor(String sourceType) => switch (sourceType) {
    'SEND_MONEY' => typeSendMoney,
    'PAYBILL' => typePaybill,
    'BUY_GOODS' => typeBuyGoods,
    'CASH' => typeCash,
    _ => mutedInk,
  };

  static const light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF0A6E8A), // Ocean; white text 5.82:1
    onPrimary: Color(0xFFFFFFFF),
    deep: Color(0xFF073B4C), // Deep ocean
    backBg: Color(0xFF073B4C),
    backInk: Color(0xFFFFFFFF),
    tint: Color(0xFFE0F1F5), // Ocean tint
    tintInk: Color(0xFF073B4C),
    brightPill: Color(0xFF1597B8), // Bright ocean
    dotIdle: Color(0xFFC3CFD3),
    ink: Color(0xFF13262E),
    softInk: Color(0xFF3E5058),
    mutedInk: Color(0xFF5B6B72),
    background: Color(0xFFF4F8F9), // Mist
    surface: Color(0xFFFFFFFF),
    textCard: Color(0xFFE8F0F2),
    line: Color(0xFFD3DFE3),
    frameLine: Color(0xFFB5D6DF),
    skipBg: Color(0xD9FFFFFF), // rgba(255,255,255,.85)
    skipInk: Color(0xFF073B4C),
    sun: AppColors.sun,
    card: Color(0xFFFFFFFF),
    track: Color(0xFFE8F0F2),
    diffUp: Color(0xFFC62828),
    diffDown: Color(0xFF0A6E8A),
    typeSendMoney: Color(0xFF1283A3),
    typePaybill: Color(0xFF5B4FC4),
    typeBuyGoods: Color(0xFFC2366B),
    typeCash: Color(0xFFB07800),
    bar: Color(0xFF9CC9D6),
    barOn: Color(0xFF0A6E8A),
    highlight: Color(0xFFFFF4D6),
    toastAction: Color(0xFF8FD3E6),
    onDelete: Color(0xFFFFFFFF),
    onTypeColor: Color(0xFFFFFFFF),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF3FB6D4), // Bright ocean; dark text 7.03:1
    onPrimary: Color(0xFF06212B),
    deep: Color(0xFFBFE4EE),
    backBg: Color(0xFFCFE9F0), // Pale ocean
    backInk: Color(0xFF073B4C), // 9.53:1
    tint: Color(0xFF133640), // Deep tint
    tintInk: Color(0xFFBFE4EE),
    brightPill: Color(0xFF3FB6D4),
    dotIdle: Color(0xFF3A4E56),
    ink: Color(0xFFE6F0F3), // Light ink
    softInk: Color(0xFFA3B7BF),
    mutedInk: Color(0xFFA3B7BF),
    background: Color(0xFF0E1A1F), // Night
    surface: Color(0xFF0E1A1F),
    textCard: Color(0xFF1A2C34), // Night card
    line: Color(0xFF2E444D),
    frameLine: Color(0xFF2E5561),
    skipBg: Color(0xEB1A2C34), // rgba(26,44,52,.92)
    skipInk: Color(0xFFBFE4EE),
    sun: AppColors.sun,
    card: Color(0xFF1A2C34), // Night card
    track: Color(0xFF0E1A1F),
    diffUp: Color(0xFFFF8A80),
    diffDown: Color(0xFF3FB6D4),
    typeSendMoney: Color(0xFF2AA3C4),
    typePaybill: Color(0xFF8479E8),
    typeBuyGoods: Color(0xFFE0628F),
    typeCash: Color(0xFFBF8A00),
    bar: Color(0xFF2E5561),
    barOn: Color(0xFF3FB6D4),
    highlight: Color(0xFF3A3320),
    toastAction: Color(0xFF2E5561),
    onDelete: Color(0xFF2A0E0C),
    onTypeColor: Color(0xFF0E1A1F), // Night; dark initials so >= 3:1 on every type colour
  );

  // --- Leaf & Gold (T23): the
  // brand-free Safaricom-style green alternative, same field-for-field
  // shape as [light]/[dark]. ---

  static const leafLight = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF007A3D),
    onPrimary: Color(0xFFFFFFFF),
    deep: Color(0xFF004D26),
    backBg: Color(0xFF004D26),
    backInk: Color(0xFFFFFFFF),
    tint: Color(0xFFE2F4E9),
    tintInk: Color(0xFF004D26),
    brightPill: Color(0xFF00A651),
    dotIdle: Color(0xFFC4D3CA),
    ink: Color(0xFF12261A),
    softInk: Color(0xFF3E5446),
    mutedInk: Color(0xFF5A6D61),
    background: Color(0xFFF4F8F5),
    surface: Color(0xFFFFFFFF),
    textCard: Color(0xFFE8F1EB),
    line: Color(0xFFD3E0D7),
    frameLine: Color(0xFFB3D9C0),
    skipBg: Color(0xD9FFFFFF),
    skipInk: Color(0xFF004D26),
    sun: AppColors.sun,
    card: Color(0xFFFFFFFF),
    track: Color(0xFFE8F1EB),
    diffUp: Color(0xFFC62828),
    diffDown: Color(0xFF007A3D),
    typeSendMoney: Color(0xFF0E8A4A),
    typePaybill: Color(0xFF3D6FD6),
    typeBuyGoods: Color(0xFFC2366B),
    typeCash: Color(0xFFB07800),
    bar: Color(0xFFA6D8B9),
    barOn: Color(0xFF007A3D),
    highlight: Color(0xFFFFF4D6),
    toastAction: Color(0xFF9FE0B8),
    onDelete: Color(0xFFFFFFFF),
    onTypeColor: Color(0xFFFFFFFF),
  );

  static const leafDark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF3DCB7E),
    onPrimary: Color(0xFF062B16),
    deep: Color(0xFFC3EDD3),
    backBg: Color(0xFFD0F0DC),
    backInk: Color(0xFF004D26),
    tint: Color(0xFF12361F),
    tintInk: Color(0xFFC3EDD3),
    brightPill: Color(0xFF3DCB7E),
    dotIdle: Color(0xFF3A5244),
    ink: Color(0xFFE6F2EA),
    softInk: Color(0xFFA5BBAD),
    mutedInk: Color(0xFFA5BBAD),
    background: Color(0xFF0E1A13),
    surface: Color(0xFF0E1A13),
    textCard: Color(0xFF1A2C21),
    line: Color(0xFF2E4A39),
    frameLine: Color(0xFF2E5A40),
    skipBg: Color(0xEB1A2C21),
    skipInk: Color(0xFFC3EDD3),
    sun: AppColors.sun,
    card: Color(0xFF1A2C21),
    track: Color(0xFF0E1A13),
    diffUp: Color(0xFFFF8A80),
    diffDown: Color(0xFF3DCB7E),
    typeSendMoney: Color(0xFF2FB36A),
    typePaybill: Color(0xFF7FA2F0),
    typeBuyGoods: Color(0xFFE0628F),
    typeCash: Color(0xFFBF8A00),
    bar: Color(0xFF2E5A40),
    barOn: Color(0xFF3DCB7E),
    highlight: Color(0xFF3A3320),
    toastAction: Color(0xFF2E5A40),
    onDelete: Color(0xFF2A0E0C),
    onTypeColor: Color(0xFF0E1A13),
  );

  // --- Indigo & Peach (T23). ---

  static const indigoLight = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF4F46E5),
    onPrimary: Color(0xFFFFFFFF),
    deep: Color(0xFF312E81),
    backBg: Color(0xFF312E81),
    backInk: Color(0xFFFFFFFF),
    tint: Color(0xFFECEBFD),
    tintInk: Color(0xFF312E81),
    brightPill: Color(0xFF6D66F0),
    dotIdle: Color(0xFFCACAE0),
    ink: Color(0xFF1E1B3A),
    softInk: Color(0xFF45425F),
    mutedInk: Color(0xFF5E5B78),
    background: Color(0xFFF7F7FB),
    surface: Color(0xFFFFFFFF),
    textCard: Color(0xFFEEEEF7),
    line: Color(0xFFDCDCEA),
    frameLine: Color(0xFFC4C1F2),
    skipBg: Color(0xD9FFFFFF),
    skipInk: Color(0xFF312E81),
    sun: Color(0xFFFF9F7A),
    card: Color(0xFFFFFFFF),
    track: Color(0xFFEEEEF7),
    diffUp: Color(0xFFC62828),
    diffDown: Color(0xFF4F46E5),
    typeSendMoney: Color(0xFF5B54E8),
    typePaybill: Color(0xFF0C77A6),
    typeBuyGoods: Color(0xFFC0397F),
    typeCash: Color(0xFF9A5B06),
    bar: Color(0xFFB9B5F5),
    barOn: Color(0xFF4F46E5),
    highlight: Color(0xFFFFEDE4),
    toastAction: Color(0xFFB9B5F5),
    onDelete: Color(0xFFFFFFFF),
    onTypeColor: Color(0xFFFFFFFF),
  );

  static const indigoDark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF8F89FF),
    onPrimary: Color(0xFF15123A),
    deep: Color(0xFFD6D3FF),
    backBg: Color(0xFFDEDCFF),
    backInk: Color(0xFF312E81),
    tint: Color(0xFF25224A),
    tintInk: Color(0xFFD6D3FF),
    brightPill: Color(0xFF8F89FF),
    dotIdle: Color(0xFF3E3B5E),
    ink: Color(0xFFECEBF7),
    softInk: Color(0xFFB0AECB),
    mutedInk: Color(0xFFB0AECB),
    background: Color(0xFF12111F),
    surface: Color(0xFF12111F),
    textCard: Color(0xFF1F1D33),
    line: Color(0xFF35325A),
    frameLine: Color(0xFF3F3A78),
    skipBg: Color(0xEB1F1D33),
    skipInk: Color(0xFFD6D3FF),
    sun: Color(0xFFFF9F7A),
    card: Color(0xFF1F1D33),
    track: Color(0xFF12111F),
    diffUp: Color(0xFFFF8A80),
    diffDown: Color(0xFF8F89FF),
    typeSendMoney: Color(0xFF8F89FF),
    typePaybill: Color(0xFF3FA9D9),
    typeBuyGoods: Color(0xFFE0628F),
    typeCash: Color(0xFFC98A3A),
    bar: Color(0xFF3F3A78),
    barOn: Color(0xFF8F89FF),
    highlight: Color(0xFF3D2A22),
    toastAction: Color(0xFF3F3A78),
    onDelete: Color(0xFF2A0E0C),
    onTypeColor: Color(0xFF12111F),
  );

  /// The token set for [brightness].
  static AppPalette forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// The token set for [id] (`AppPalettes.byId`) at [brightness]. Unknown
  /// ids fall back to `ocean`, same as a corrupt stored preference
  /// (`AppPrefs.readPaletteId`).
  static AppPalette forId(String id, Brightness brightness) => AppPalettes.byId(id).forBrightness(brightness);

  /// The chosen palette (T23: `AppPaletteScope`, app-wide) at the phone's
  /// current light/dark setting. Rebuilds the caller when either changes.
  /// Applies app-wide (T26 "i think it should recolor the entire app",
  /// superseding T23's "only reworked pages" rule): every reworked page,
  /// including Welcome, onboarding and now Add (T27), calls this.
  static AppPalette of(BuildContext context) =>
      forId(AppPaletteScope.of(context).value, MediaQuery.platformBrightnessOf(context));

  /// The system bars for the primary pages (T21, backlog "System bars
  /// break the seamless top"): a transparent status bar with no contrast
  /// scrim, so the seamless top bar runs up under it, and a gesture/nav bar
  /// in the bottom nav's [card] colour instead of black. Icons are dark on
  /// the light theme and light on the dark theme.
  SystemUiOverlayStyle get systemOverlayStyle => overlayStyleWithNavBar(card);

  /// [systemOverlayStyle] with the system nav bar in [navBarColor] — for
  /// full-screen pages whose bottom edge isn't the bottom nav (Welcome,
  /// onboarding).
  SystemUiOverlayStyle overlayStyleWithNavBar(Color navBarColor) {
    final dark = brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: icons,
      // iOS reads the bar's own brightness (the opposite of the icons').
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: navBarColor,
      systemNavigationBarDividerColor: navBarColor,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }
}

/// One selectable palette (T23): an id, a display name, and its light +
/// dark [AppPalette] token sets. See [AppPalettes] for the three shipped
/// sets.
@immutable
class AppPaletteSet {
  const AppPaletteSet({required this.id, required this.name, required this.light, required this.dark});

  /// Stable id, also the `AppPrefs` stored value (`ocean` | `leaf` |
  /// `indigo`).
  final String id;

  /// Display name (Settings' radio tile label).
  final String name;

  final AppPalette light;
  final AppPalette dark;

  /// The set's own token set for [brightness] — independent of any chosen
  /// app palette (used for the Settings preview swatches, which must show
  /// each option's true colours regardless of which one is active).
  AppPalette forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// The registry of selectable palettes (T23 "a WORKING switch in
/// Settings", PM direct decision, 2026-09-26; values from
/// the approved palette set, v0.1.0). `ocean` is today's
/// [AppPalette.light]/[AppPalette.dark], unchanged.
class AppPalettes {
  AppPalettes._();

  static const ocean = AppPaletteSet(id: 'ocean', name: 'Ocean & Sun', light: AppPalette.light, dark: AppPalette.dark);

  /// Deliberately brand-free name (not "Safaricom green") — PM direct
  /// decision, 2026-09-26.
  static const leaf = AppPaletteSet(
    id: 'leaf',
    name: 'Leaf & Gold',
    light: AppPalette.leafLight,
    dark: AppPalette.leafDark,
  );

  static const indigo = AppPaletteSet(
    id: 'indigo',
    name: 'Indigo & Peach',
    light: AppPalette.indigoLight,
    dark: AppPalette.indigoDark,
  );

  /// In Settings' display order.
  static const all = <AppPaletteSet>[ocean, leaf, indigo];

  /// [id] resolved to its set. An unknown or corrupt id falls back to
  /// [ocean] (T23 scope rule: unknown/corrupt stored id -> ocean).
  static AppPaletteSet byId(String id) => switch (id) {
    'leaf' => leaf,
    'indigo' => indigo,
    _ => ocean,
  };
}
