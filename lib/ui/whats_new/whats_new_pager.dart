import 'dart:async';

import 'package:flutter/material.dart';

import '../copy/whats_new_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../screens/backup/backup_sheet_shell.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';
import 'whats_new_cards.dart';

/// §UI.WHATSNEW.PAGER — the What's-new pager (0.1.2 S11a, WN1, A1-A5). ONE
/// widget, shown the same way from Home (the pop-up after an update) and from
/// the Updates entry: a bottom sheet that an outside tap or a drag cannot
/// close. Five cards; swipe, Next and Back move between them; the system Back
/// key steps back one card and, on the first card, closes WITHOUT marking
/// anything seen. Only the last card has "Got it". The buttons are pinned and
/// the card scrolls ([BackupSheetShell]).

/// What this process knows about the pager (not stored anywhere).
class WhatsNewProcess {
  WhatsNewProcess._();

  /// The pop-up was shown in this process: a second Home start (a restart
  /// scope) does not show it again. It comes back at the next cold start until
  /// Got it.
  static bool autoShown = false;

  /// The NEW pill on the Updates entry was cleared in this process (the user
  /// left Updates, or tapped Got it). No pref key: it comes back at a cold
  /// start until the installed version is marked seen.
  static bool pillCleared = false;

  static bool _open = false;

  /// True while a pager is on screen.
  static bool get isOpen => _open;

  static void resetForTest() {
    autoShown = false;
    pillCleared = false;
    _open = false;
  }
}

/// Shows the pager over [context]'s page. Resolves to true only for "Got it";
/// the first-card Back resolves to false (nothing is marked seen). A second
/// call while one is open does nothing and resolves to false.
///
/// [onOpenSettings] and [onOpenBackup] are the callers' route openers: they
/// push OVER the pager, Back returns to the same card, and nothing is marked
/// seen.
Future<bool> showWhatsNewPager(
  BuildContext context, {
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenBackup,
}) async {
  if (WhatsNewProcess.isOpen) return false;
  WhatsNewProcess._open = true;
  try {
    final result = await showBackupSheet<bool>(
      context,
      (_) => WhatsNewPager(onOpenSettings: onOpenSettings, onOpenBackup: onOpenBackup),
      dismissible: false,
    );
    return result ?? false;
  } finally {
    WhatsNewProcess._open = false;
  }
}

/// Writes the installed version as seen. NOT awaited by the caller's UI: a 2 s
/// timeout, and a failure leaves the pager unseen, silently.
void writeSeenQuietly(Future<void> Function(String versionName) write, String installed) {
  unawaited(() async {
    try {
      await write(installed).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }());
}

class WhatsNewPager extends StatefulWidget {
  const WhatsNewPager({super.key, required this.onOpenSettings, required this.onOpenBackup});

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenBackup;

  @override
  State<WhatsNewPager> createState() => _WhatsNewPagerState();
}

class _WhatsNewPagerState extends State<WhatsNewPager> {
  final _titleFocus = FocusNode(debugLabel: 'whatsNewCardTitle');
  final _scroll = ScrollController();
  int _index = 0;

  static const _last = kWhatsNewCardCount - 1;

  @override
  void initState() {
    super.initState();
    _focusTitleNextFrame();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A new card: scroll to its top and move focus to its title.
  void _focusTitleNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _titleFocus.requestFocus();
    });
  }

  void _go(int to) {
    if (to < 0 || to > _last || to == _index) return;
    setState(() => _index = to);
    _focusTitleNextFrame();
  }

  void _next() => _go(_index + 1);
  void _prev() => _go(_index - 1);

  /// The system Back key: previous card; on card 1 close, nothing marked seen.
  void _onBack() {
    if (_index > 0) {
      _prev();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  void _gotIt() => Navigator.of(context).pop(true);

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -200) {
      _next();
    } else if (v > 200) {
      _prev();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isLast = _index == _last;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: GestureDetector(
        key: const Key('whatsNewPager'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _onSwipe,
        child: BackupSheetShell(
          palette: palette,
          title: kWhatsNewPagerTitle,
          titleKey: const Key('whatsNewPagerTitle'),
          scrollController: _scroll,
          body: [
            _Dots(palette: palette, index: _index),
            WhatsNewCardView(
              index: _index,
              palette: palette,
              titleFocus: _titleFocus,
              onOpenSettings: widget.onOpenSettings,
              onOpenBackup: widget.onOpenBackup,
            ),
          ],
          actions: SheetActions(
            secondary: _index > 0
                ? OutlinedButton(
                    key: const Key('whatsNewBack'),
                    onPressed: _prev,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                      foregroundColor: palette.primary,
                    ),
                    child: const Text('Back'),
                  )
                : null,
            primary: FilledButton(
              key: Key(isLast ? 'whatsNewGotIt' : 'whatsNewNext'),
              onPressed: isLast ? _gotIt : _next,
              style: FilledButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
              ),
              child: Text(isLast ? kWhatsNewGotIt : 'Next'),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page dots: not tappable; one label says which card this is.
class _Dots extends StatelessWidget {
  const _Dots({required this.palette, required this.index});

  final AppPalette palette;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: whatsNewCardOfText(index + 1),
      excludeSemantics: true,
      child: Row(
        key: const Key('whatsNewDots'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kWhatsNewCardCount; i++)
            Container(
              key: Key('whatsNewDot$i'),
              width: 9,
              height: 9,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i == index ? palette.primary : palette.track),
            ),
        ],
      ),
    );
  }
}
