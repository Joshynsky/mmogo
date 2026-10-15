import 'package:flutter/widgets.dart';

import '../../data/prefs/app_prefs.dart';

/// The app-wide chosen palette id (`ocean` | `leaf` | `indigo`; T23 "a
/// WORKING switch in Settings") and, since 0.1.2 S9a (AP1), the chosen
/// appearance (`system` | `light` | `dark`). Holds ids only —
/// `AppPalette.of` resolves them (plus the phone's brightness when the
/// appearance is `system`) into real tokens; this class never touches colours.
///
/// Starts at `ocean` / `system` (the safe defaults while [load] is in flight)
/// and is loaded from `AppPrefs` once at app startup (`main`, BEFORE the first
/// frame so there is no flash of the wrong theme). Every [select] /
/// [selectAppearance] persists immediately (fire-and-forget, same discipline
/// as `AppPrefs.writeAutoRecognizeClassifications`: a failed/stuck write never
/// blocks the UI, which already reflects the new value).
///
/// The palette id is the notifier's [value]; the appearance is a second field
/// that notifies the same listeners.
class AppPaletteController extends ValueNotifier<String> {
  AppPaletteController([super.value = 'ocean', String appearance = 'system']) : _appearance = appearance;

  String _appearance;

  /// `system` (follow the phone, the default) | `light` | `dark`.
  String get appearance => _appearance;

  /// Reads the stored palette id and appearance (defensive: a missing/corrupt/
  /// unreadable value already resolves to `ocean` / `system` inside `AppPrefs`).
  Future<void> load() async {
    final loaded = await Future.wait<String>([AppPrefs.readPaletteId(), AppPrefs.readAppearanceMode()]);
    _appearance = loaded[1];
    value = loaded[0];
    notifyListeners();
  }

  /// Applies [id] at once (Settings' radio tiles) and persists it in the
  /// background.
  void select(String id) {
    if (id == value) return;
    value = id;
    AppPrefs.writePaletteId(id);
  }

  /// Applies the appearance at once (Settings' three icons) and persists it in
  /// the background. Device-only: never in a backup.
  void selectAppearance(String mode) {
    if (mode == _appearance || (mode != 'system' && mode != 'light' && mode != 'dark')) return;
    _appearance = mode;
    notifyListeners();
    AppPrefs.writeAppearanceMode(mode);
  }

  /// The brightness the app draws in: the chosen appearance, or [phone] when
  /// it is `system`.
  Brightness brightnessFor(Brightness phone) => switch (_appearance) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => phone,
  };
}

/// Publishes an [AppPaletteController] down the tree as an
/// `InheritedNotifier`, so `AppPalette.of(context)` rebuilds its caller
/// whenever the chosen palette or appearance changes — the same dependency
/// shape `MediaQuery` gives brightness changes.
class AppPaletteScope extends InheritedNotifier<AppPaletteController> {
  const AppPaletteScope({super.key, required AppPaletteController controller, required super.child})
    : super(notifier: controller);

  /// The nearest controller, or `null` if [context] has none above it.
  /// Establishes a rebuild dependency either way (so a widget that calls
  /// this before one is ever mounted still updates once it is).
  static AppPaletteController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPaletteScope>()?.notifier;

  /// The nearest controller. `MpesaTrackerApp` always provides one in the
  /// real app; a caller with no `AppPaletteScope` above it (most existing
  /// widget tests, which pump a screen directly under a bare `MaterialApp`)
  /// gets a fresh, unpersisted `ocean` / `system` controller instead of a hard
  /// failure — the same "missing -> ocean" fallback `AppPrefs.readPaletteId`
  /// already applies to a missing/corrupt stored id.
  static AppPaletteController of(BuildContext context) => maybeOf(context) ?? AppPaletteController();
}
