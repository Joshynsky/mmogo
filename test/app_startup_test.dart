// 0.1.2 S9b-1: the pinned start-up ORDER. A pending "Reset app" is finished
// before the palette load and before anything opens the database. Uses
// recording fakes only; the real ResetResume is never called here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_startup.dart';

void main() {
  test('bootstrapApp runs the resume FIRST, then the palette load', () async {
    final order = <String>[];
    final c = await bootstrapApp(
      resume: () async {
        order.add('resume');
        return true;
      },
      loadPalette: (c) async => order.add('palette'),
    );
    expect(order, ['resume', 'palette']);
    expect(c.value, 'ocean');
  });

  test('the resume is awaited: the palette load does not start while it is running', () async {
    final order = <String>[];
    await bootstrapApp(
      resume: () async {
        order.add('resume start');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('resume end');
        return false;
      },
      loadPalette: (c) async => order.add('palette'),
    );
    expect(order, ['resume start', 'resume end', 'palette']);
  });

  test('a throwing resume or palette never blocks start-up', () async {
    final c = await bootstrapApp(
      resume: () async => throw StateError('x'),
      loadPalette: (c) async => throw StateError('y'),
    );
    expect(c.value, 'ocean');
  });

  test('source order: main() calls bootstrapApp right after ensureInitialized and before runApp; the resume line precedes the palette line', () {
    final main = File('lib/main.dart').readAsStringSync();
    final init = main.indexOf('WidgetsFlutterBinding.ensureInitialized()');
    final boot = main.indexOf('bootstrapApp()');
    final run = main.indexOf('runApp(');
    expect(init, greaterThan(-1));
    expect(boot, greaterThan(init));
    expect(run, greaterThan(boot));
    expect(main.substring(init, boot).contains('AppDatabase'), isFalse);

    final startup = File('lib/app_startup.dart').readAsStringSync();
    final resume = startup.indexOf('ResetResume.runIfPending');
    final palette = startup.indexOf('c.load()');
    expect(resume, greaterThan(-1));
    expect(palette, greaterThan(resume));
    expect(startup.contains('AppDatabase'), isFalse, reason: 'nothing here may open the database');
  });
}
