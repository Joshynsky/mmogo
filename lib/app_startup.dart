import 'data/maintenance/reset_resume.dart';
import 'ui/theme/app_palette_scope.dart';

/// §APP.STARTUP — what `main()` runs after `WidgetsFlutterBinding.ensureInitialized()`
/// and before `runApp` (0.1.2 S9b-1). The ORDER is pinned by a test:
///
///  1. [ResetResume.runIfPending] — finishes a "Reset app" that was cut short.
///     It must come first: nothing may open the database, read a preference
///     or run the open-failure gate (OF1, S10) before a pending reset is done.
///  2. the palette / Appearance load (S9a), so a dark choice never flashes light.
///
/// Both parameters are test seams; a failed step never blocks start-up.
Future<AppPaletteController> bootstrapApp({
  Future<bool> Function()? resume,
  Future<void> Function(AppPaletteController controller)? loadPalette,
}) async {
  try {
    await (resume ?? ResetResume.runIfPending)();
  } catch (_) {
    // ResetResume never throws; belt and braces: start-up must go on.
  }
  final controller = AppPaletteController();
  try {
    await (loadPalette ?? (c) => c.load())(controller);
  } catch (_) {}
  return controller;
}
