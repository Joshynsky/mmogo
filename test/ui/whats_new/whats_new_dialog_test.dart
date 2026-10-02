// B31: the What's-new modal: shown once on the first launch after an update,
// never on a fresh install, dismissable, remembers the version, and can open
// Backup and restore. Prefs come from the mock store (no platform channels).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/whats_new_copy.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/whats_new/whats_new_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dialog = Key('whatsNewDialog');

/// Pumps a page that runs the Home hook once on first build.
Future<void> _pump(WidgetTester tester, {required Map<String, Object> prefs, String installed = '0.1.1'}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      routes: {Routes.backup: (_) => const Scaffold(body: Text('BACKUP PAGE'))},
      home: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) maybeShowWhatsNew(context, installedVersionName: installed);
          });
          return const Scaffold(body: Text('HOME'));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('readable in dark mode', () {
    // Dialogs follow the palette (PaletteAlertDialog): in dark mode the body
    // text must contrast with the dark card. Found on a phone in dark mode
    // when the dialog was still a pale card with pale text.
    testWidgets('body text contrasts with the dialog surface when the phone is dark', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.dark),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) maybeShowWhatsNew(context, installedVersionName: '0.1.1');
              });
              return const Scaffold(body: Text('HOME'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dialogContext = tester.element(find.byKey(_dialog));
      final surface = AppPalette.of(dialogContext).card;
      final body = tester.widget<RichText>(
        find.descendant(of: find.byKey(_dialog), matching: find.byType(RichText)).at(1),
      );
      final ink = body.text.style?.color ?? DefaultTextStyle.of(dialogContext).style.color;
      expect(ink, isNotNull);
      final a = surface.computeLuminance();
      final b = ink!.computeLuminance();
      final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
      expect(ratio, greaterThan(4.5));
    });
  });

  group('who sees it', () {
    testWidgets('an upgrade from 0.1.0 (nothing stored, onboarding done) sees it', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true});
      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.text(kWhatsNewTitle), findsOneWidget);
    });

    testWidgets('a fresh install (nothing stored, onboarding not done) never sees it', (tester) async {
      await _pump(tester, prefs: {});
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('a version already seen is not shown again', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true, 'whatsnew_seen_version': '0.1.1'});
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('an older seen version shows it', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true, 'whatsnew_seen_version': '0.1.0'});
      expect(find.byKey(_dialog), findsOneWidget);
    });

    testWidgets('a version with no bundled text never shows it', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true}, installed: '0.1.2');
      expect(find.byKey(_dialog), findsNothing);
    });
  });

  group('the modal', () {
    testWidgets('modal_text_contains_uninstall_and_phone_transfer_sentence (and the network sentence)', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true});
      final text = tester
          .widgetList<RichText>(find.descendant(of: find.byKey(_dialog), matching: find.byType(RichText)))
          .map((r) => r.text.toPlainText())
          .join('\n');
      expect(text, contains(kUninstallErasesNotice));
      expect(text, contains(kPhoneTransferNotice));
      expect(text, contains(kNetworkSentence));
      expect(text, contains(kUpdateCheckCadence));
      expect(text, contains('Updates page (Profile, Settings, Updates)'));
      expect(text, contains('not encrypted'));
      expect(text, contains('a dot on the bell on Home'));
      expect(text.toLowerCase(), isNot(contains('nothing is sent anywhere')));
      expect(text.toLowerCase(), isNot(contains('no permissions')));
    });

    testWidgets('has both buttons', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true});
      expect(find.text(kWhatsNewGotIt), findsOneWidget);
      expect(find.text(kWhatsNewOpenBackup), findsOneWidget);
    });

    testWidgets('modal_shows_once: Got it closes it, remembers 0.1.1, and a second hook run shows nothing', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true});
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), '0.1.1');

      // The next launch.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) maybeShowWhatsNew(context, installedVersionName: '0.1.1');
              });
              return const Scaffold(body: Text('HOME AGAIN'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('Open Backup and restore: remembers the version and opens that page', (tester) async {
      await _pump(tester, prefs: {'onboarding_complete': true});
      await tester.tap(find.byKey(const Key('whatsNewOpenBackup')));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(find.text('BACKUP PAGE'), findsOneWidget);
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), '0.1.1');
    });

    testWidgets('a failed write never throws or blocks closing', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  maybeShowWhatsNew(
                    context,
                    installedVersionName: '0.1.1',
                    writeSeenVersion: (_) async => throw StateError('disk full'),
                  );
                }
              });
              return const Scaffold(body: Text('HOME'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
