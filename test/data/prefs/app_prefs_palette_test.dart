// T23 cheap tests for AppPrefs.readPaletteId/writePaletteId: the round trip
// and the "unknown/corrupt stored id falls back to ocean" defensive rule
// the build brief calls out explicitly.
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/prefs/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to ocean when nothing is stored', () async {
    expect(await AppPrefs.readPaletteId(), 'ocean');
  });

  test('round-trips each valid id', () async {
    for (final id in ['ocean', 'leaf', 'indigo']) {
      await AppPrefs.writePaletteId(id);
      expect(await AppPrefs.readPaletteId(), id);
    }
  });

  test('a corrupt/unrecognised stored id falls back to ocean', () async {
    SharedPreferences.setMockInitialValues({AppPrefs.keyPaletteId: 'not-a-real-palette'});
    expect(await AppPrefs.readPaletteId(), 'ocean');
  });

  test('an empty-string stored id falls back to ocean', () async {
    SharedPreferences.setMockInitialValues({AppPrefs.keyPaletteId: ''});
    expect(await AppPrefs.readPaletteId(), 'ocean');
  });
}
