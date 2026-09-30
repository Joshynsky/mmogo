import 'package:flutter/widgets.dart';

import '../../data/prefs/app_prefs.dart';

/// The app-wide chosen palette id (`ocean` | `leaf` | `indigo`; T23 "a
/// WORKING switch in Settings"). Holds the id only — `AppPalette.of`
/// resolves it (plus the phone's brightness) into real tokens; this class
/// never touches colours.
///
/// Starts at `ocean` (the safe default while [load] is in flight) and is
/// loaded from `AppPrefs` once at app startup ([MpesaTrackerApp]). Every
/// [select] persists immediately (fire-and-forget, same discipline as
/// `AppPrefs.writeAutoRecognizeClassifications`: a failed/stuck write never
/// blocks the UI, which already reflects the new value).
class AppPaletteController extends ValueNotifier<String> {
  AppPaletteController([super.value = 'ocean']);

  /// Reads the stored id (defensive: a missing/corrupt/unreadable value
  /// already resolves to `ocean` inside `AppPrefs.readPaletteId`).
  Future<void> load() async {
    value = await AppPrefs.readPaletteId();
  }

  /// Applies [id] at once (Settings' radio tiles) and persists it in the
  /// background.
  void select(String id) {
    if (id == value) return;
    value = id;
    AppPrefs.writePaletteId(id);
  }
}

/// Publishes an [AppPaletteController] down the tree as an
/// `InheritedNotifier`, so `AppPalette.of(context)` rebuilds its caller
/// whenever the chosen palette changes — the same dependency shape
/// `MediaQuery` gives brightness changes.
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
  /// gets a fresh, unpersisted `ocean` controller instead of a hard
  /// failure — the same "missing -> ocean" fallback `AppPrefs.readPaletteId`
  /// already applies to a missing/corrupt stored id.
  static AppPaletteController of(BuildContext context) => maybeOf(context) ?? AppPaletteController();
}
