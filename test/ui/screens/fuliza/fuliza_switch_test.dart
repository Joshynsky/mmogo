// 0.2.0 S12 slice C (Judge C6 B): the Fuliza kill-switch (pref fuliza_show, default on) and the Rebuild button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/fuliza/fuliza_rebuild.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/ui/copy/settings_copy.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_screen.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_source.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_visible.dart';
import 'package:mmogo/ui/screens/settings/adding_section.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_analytics_db.dart';

void main() {
  setUp(() {
    fulizaVisible = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    fulizaVisible = false;
    FulizaSource.repository = null;
    FulizaRebuild.hook = null;
  });

  test('default is on; off makes load return null but events stay and can still be saved', () async {
    final repo = InMemoryFulizaRepository();
    await repo.addEvent(
      FulizaEvent(
        kind: FulizaEventKind.draw,
        code: 'QDMFS00001',
        at: DateTime(2026, 11, 2),
        amountCents: 100000,
        feeCents: 1000,
        printedTotalCents: 101000,
      ),
    );
    FulizaSource.repository = repo;
    final db = FakeAnalyticsDb(analyticsSampleRows());
    expect(AppPrefs.keyFulizaShow, 'fuliza_show');
    expect(await FulizaSource.readShow(), isTrue);
    expect(await FulizaSource.load(db), isNotNull);

    await FulizaSource.writeShow(false);
    expect(await FulizaSource.readShow(), isFalse);
    expect(await FulizaSource.load(db), isNull);
    expect((await repo.events()).length, 1);
    final saved = await repo.addEvent(
      FulizaEvent(kind: FulizaEventKind.repayFull, code: 'QDMFS00002', at: DateTime(2026, 11, 3), amountCents: 5000),
    );
    expect(saved, isTrue, reason: 'saving is not affected by the switch (C6 B)');
    expect((await repo.events()).length, 2);

    await FulizaSource.writeShow(true);
    expect(await FulizaSource.load(db), isNotNull);
  });

  testWidgets('the Settings row shows its wording and toggles the value', (t) async {
    var value = true;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => SingleChildScrollView(
              child: AddingSection(
                palette: AppPalette.of(c),
                tourKey: GlobalKey(),
                autoRecognize: true,
                onAutoRecognizeChanged: (_) {},
                captureReceiver: true,
                onCaptureReceiverChanged: (_) {},
                showFuliza: value,
                onShowFulizaChanged: (v) => set(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text(kShowFulizaLabel), findsOneWidget);
    expect(kShowFulizaLabel, 'Show Fuliza');
    expect(find.text(kShowFulizaSubtitle), findsOneWidget);
    await t.tap(find.byKey(const Key('settingsShowFuliza')));
    await t.pump();
    expect(value, isFalse);
  });

  testWidgets('Rebuild button runs the hook and says how many were added', (t) async {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var calls = 0;
    FulizaRebuild.hook = () async {
      calls++;
      return 2;
    };
    await t.pumpWidget(MaterialApp(home: FulizaScreen(loader: () async => null)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fulizaRebuild')));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Added 2 records. Only messages mmogo still holds can be used.'), findsOneWidget);
  });

  group('hidden in 0.2.0 (default)', () {
    test('the visibility switch is off by default', () {
      fulizaVisible = false;
      expect(fulizaVisible, isFalse);
    });

    test('load returns null even with stored events and the pref on; capture still saves', () async {
      fulizaVisible = false;
      final repo = InMemoryFulizaRepository();
      await repo.addEvent(
        FulizaEvent(
          kind: FulizaEventKind.draw,
          code: 'QDMFS00001',
          at: DateTime(2026, 11, 2),
          amountCents: 100000,
          feeCents: 1000,
          printedTotalCents: 101000,
        ),
      );
      FulizaSource.repository = repo;
      expect(await FulizaSource.load(FakeAnalyticsDb(analyticsSampleRows())), isNull);
      final saved = await repo.addEvent(
        FulizaEvent(kind: FulizaEventKind.repayFull, code: 'QDMFS00002', at: DateTime(2026, 11, 3), amountCents: 5000),
      );
      expect(saved, isTrue);
      expect((await repo.events()).length, 2);
    });

    testWidgets('the Settings card has no Show Fuliza row', (t) async {
      fulizaVisible = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AddingSection(
                palette: AppPalette.light,
                tourKey: GlobalKey(),
                autoRecognize: true,
                onAutoRecognizeChanged: (_) {},
                captureReceiver: true,
                onCaptureReceiverChanged: (_) {},
                showFuliza: true,
                onShowFulizaChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('settingsShowFuliza')), findsNothing);
      expect(find.textContaining('Fuliza'), findsNothing);
    });
  });
}
