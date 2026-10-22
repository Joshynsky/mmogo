import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_constants.dart';
import '../../platform/storage_bridge.dart';
import '../copy/data_copy.dart';
import '../copy/whats_new_copy.dart';
import '../copy/whats_new_pager_copy.dart';
import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';
import 'whats_new_cards.dart';

/// §UI.WHATSNEW.PAGER — the What's-new page (0.1.2 A5a; it replaced the
/// six-card pager sheet). ONE full-screen route, shown the same way from Home
/// (the pop-up after an update) and from the Updates entry. Top to bottom: a
/// tinted banner saying which version this is, the title, one intro line, the
/// item rows (tap to open; several can be open; the first starts open) and a
/// pinned bottom bar with the one "Got it". The system Back key closes the page
/// WITHOUT marking anything seen; only "Got it" does. Opened to read (from the
/// Updates entry or its Notifications row) the bar has "Back" instead and there
/// is no "Got it": opening it there is what counts as seen.

/// What this process knows about the page (not stored anywhere).
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

  /// True while a page is on screen.
  static bool get isOpen => _open;

  static void resetForTest() {
    autoShown = false;
    pillCleared = false;
    _open = false;
  }
}

/// Shows the page over [context]'s page. Resolves to true only for "Got it";
/// Back resolves to false (nothing is marked seen). A second call while one is
/// open does nothing and resolves to false.
///
/// [onOpenSettings] and [onOpenBackup] are the callers' route openers: they
/// push OVER the page, Back returns to it as it was, and nothing is marked
/// seen. [onOpenSite] opens the mmogo page in the browser (default: the
/// storage bridge, the site URL only).
Future<bool> showWhatsNewPager(
  BuildContext context, {
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenBackup,
  VoidCallback? onOpenSite,
  bool readOnly = false,
}) async {
  if (WhatsNewProcess.isOpen) return false;
  WhatsNewProcess._open = true;
  try {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'whats-new'),
        builder: (_) => WhatsNewPage(
          onOpenSettings: onOpenSettings,
          onOpenBackup: onOpenBackup,
          onOpenSite: onOpenSite,
          readOnly: readOnly,
        ),
      ),
    );
    return result ?? false;
  } finally {
    WhatsNewProcess._open = false;
  }
}

/// Writes the installed version as seen. NOT awaited by the caller's UI: a 2 s
/// timeout, and a failure leaves the page unseen, silently.
void writeSeenQuietly(Future<void> Function(String versionName) write, String installed) {
  unawaited(() async {
    try {
      await write(installed).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }());
}

class WhatsNewPage extends StatefulWidget {
  const WhatsNewPage({
    super.key,
    required this.onOpenSettings,
    required this.onOpenBackup,
    this.onOpenSite,
    this.readOnly = false,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenBackup;
  final VoidCallback? onOpenSite;

  /// True when the page is opened to read: "Back" in place of "Got it".
  final bool readOnly;

  @override
  State<WhatsNewPage> createState() => _WhatsNewPageState();
}

class _WhatsNewPageState extends State<WhatsNewPage> {
  final _titleFocus = FocusNode(debugLabel: 'whatsNewTitle');
  final _items = whatsNewItems();
  late final Set<String> _open = {_items.first.id};

  @override
  void initState() {
    super.initState();
    // Screen readers start on the title, not on the banner or a row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
    if (!_open.remove(id)) _open.add(id);
  });

  void _gotIt() => Navigator.of(context).pop(true);

  void _back() => Navigator.of(context).pop(false);

  Future<void> _openSite() async {
    final custom = widget.onOpenSite;
    if (custom != null) {
      custom();
      return;
    }
    var opened = false;
    try {
      opened = await StorageBridge.instance.openUrl(AppConstants.siteUrl);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kUpdatesCouldNotOpen)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      key: const Key('whatsNewPager'),
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        // A plain scroll view, not a lazy list: every row is built, so a screen reader sees all of them.
        child: SingleChildScrollView(
          key: const Key('whatsNewScroll'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WhatsNewBanner(palette: palette, onOpenSite: _openSite),
              const SizedBox(height: 10),
              Focus(
                key: const Key('whatsNewTitleFocus'),
                focusNode: _titleFocus,
                child: Semantics(
                  header: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
                    child: Text(
                      kWhatsNewPagerTitle,
                      key: const Key('whatsNewPagerTitle'),
                      style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: palette.ink),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                child: Text(
                  whatsNewIntro(),
                  key: const Key('whatsNewIntro'),
                  style: TextStyle(fontSize: 13, height: 1.5, color: palette.softInk),
                ),
              ),
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                WhatsNewItemView(
                  item: _items[i],
                  number: i + 1,
                  open: _open.contains(_items[i].id),
                  palette: palette,
                  onToggle: () => _toggle(_items[i].id),
                  onOpenSettings: widget.onOpenSettings,
                  onOpenBackup: widget.onOpenBackup,
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
                child: Text(
                  kWhatsNewSignOff,
                  key: const Key('whatsNewSignOff'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        key: const Key('whatsNewBar'),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border(top: BorderSide(color: palette.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: kMinTapTarget,
              child: widget.readOnly
                  ? OutlinedButton(
                      key: const Key('whatsNewBack'),
                      onPressed: _back,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                        foregroundColor: palette.primary,
                        side: BorderSide(color: palette.primary, width: 1.5),
                      ),
                      child: const Text(kWhatsNewBack, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    )
                  : FilledButton(
                      key: const Key('whatsNewGotIt'),
                      onPressed: _gotIt,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                        backgroundColor: palette.primary,
                        foregroundColor: palette.onPrimary,
                      ),
                      child: const Text(kWhatsNewGotIt, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
