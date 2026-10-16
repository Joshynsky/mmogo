import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §SCREEN.BACKUP.SHEET_SHELL — 0.1.2 S10b (A9g, A13). The one bottom-sheet
/// frame of the Backup and restore sheets: the title (a screen-reader header
/// that also names the route), a scrolling body, and an action row PINNED
/// below the scroll area, so Cancel / Continue / Replace everything / Undo /
/// Done stay on screen with a long list or at text scale 1.3.
class BackupSheetShell extends StatelessWidget {
  const BackupSheetShell({
    super.key,
    required this.palette,
    required this.title,
    required this.body,
    this.actions,
    this.titleKey = const Key('backupSheetTitle'),
  });

  final AppPalette palette;
  final String title;
  final List<Widget> body;

  /// Pinned under the scroll area.
  final Widget? actions;

  /// The title text's key (a few sheets keep a key older tests read).
  final Key titleKey;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: title,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      key: const Key('backupSheetScroll'),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              key: titleKey,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink),
                            ),
                          ),
                          for (final w in body) ...[const SizedBox(height: 12), w],
                        ],
                      ),
                    ),
                  ),
                  if (actions != null)
                    Padding(
                      key: const Key('backupSheetActions'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: actions,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [builder] as a bottom sheet. A non-[dismissible] sheet takes no
/// outside tap and no swipe (`enableDrag` false); its builder holds a
/// `PopScope(canPop: false)` for the Back key.
Future<T?> showBackupSheet<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: builder,
  );
}

/// The pinned two-button row: [secondary] on the left, [primary] on the right.
class SheetActions extends StatelessWidget {
  const SheetActions({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (secondary != null) ...[Expanded(child: secondary!), const SizedBox(width: 10)],
        Expanded(child: primary),
      ],
    );
  }
}
