import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db/open_classifier.dart';
import '../copy/open_failure_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';

/// §SCREEN.OPEN_FAILURE — the one open-failure screen (0.1.2 S10c, M5 / OF1 /
/// CB7). Both outcomes share the layout; only the title, one sentence and the
/// code change. Shows a code only: never a stack trace, path or exception text.
///
/// Back and Close app both leave the app (`SystemNavigator.pop`). There is no
/// Restore here. Try again is the only retry and it never claims to work.
class OpenFailureScreen extends StatelessWidget {
  const OpenFailureScreen({
    super.key,
    required this.kind,
    required this.failedRetries,
    required this.trying,
    required this.onTryAgain,
  });

  final OpenFailureKind kind;

  /// How many Try again taps have failed so far (>= 1 shows "Still not working").
  final int failedRetries;

  /// A retry is running: the button is disabled and reads "Trying again...".
  final bool trying;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.of(context);
    final upg3 = kind == OpenFailureKind.rolledBackUpgrade;
    final title = upg3 ? kOpenFailTitleUpg3 : kOpenFailTitleOther;
    final body = upg3 ? kOpenFailBodyUpg3 : kOpenFailBodyOther;
    final code = upg3 ? kOpenFailCodeUpg3 : kOpenFailCodeOther;
    final small = TextStyle(color: pal.mutedInk, fontSize: 13, height: 1.4);
    final text = TextStyle(color: pal.ink, fontSize: 15, height: 1.4);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => SystemNavigator.pop(),
      child: Scaffold(
        key: const Key('openFailure'),
        backgroundColor: pal.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: pal.tint, shape: BoxShape.circle),
                        child: Icon(Icons.shield_outlined, color: pal.tintInk, size: 32),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        key: const Key('openFailTitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pal.ink, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(body, key: const Key('openFailBody'), textAlign: TextAlign.center, style: text),
                    const SizedBox(height: 16),
                    Text(kOpenFailLeadIn, key: const Key('openFailLeadIn'), style: text),
                    const SizedBox(height: 8),
                    for (var i = 0; i < kOpenFailSteps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 28, child: Text('${i + 1}.', style: text)),
                            Expanded(child: Text(kOpenFailSteps[i], style: text)),
                          ],
                        ),
                      ),
                    if (failedRetries >= 1) ...[
                      const SizedBox(height: 8),
                      Text.rich(
                        key: const Key('openFailStill'),
                        TextSpan(children: [
                          TextSpan(text: kOpenFailStillHead, style: text.copyWith(fontWeight: FontWeight.w800)),
                          const TextSpan(text: ' $kOpenFailStillTail'),
                        ]),
                        style: text,
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('openFailTryAgain'),
                      onPressed: trying ? null : onTryAgain,
                      style: FilledButton.styleFrom(
                        backgroundColor: pal.primary,
                        foregroundColor: pal.onPrimary,
                        minimumSize: const Size(0, kMinTapTarget),
                      ),
                      child: Text(trying ? kOpenFailTrying : kOpenFailTryAgain),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('openFailClose'),
                      onPressed: SystemNavigator.pop,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.ink,
                        side: BorderSide(color: pal.line),
                        minimumSize: const Size(0, kMinTapTarget),
                      ),
                      child: const Text(kOpenFailCloseApp),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      openFailCodeLine(code),
                      key: const Key('openFailCode'),
                      textAlign: TextAlign.center,
                      style: small,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
