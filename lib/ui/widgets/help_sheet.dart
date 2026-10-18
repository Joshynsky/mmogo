import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'tap_target.dart';

/// §WIDGET.HELP_SHEET — the "?" help pattern (0.1.2 review, Group A, F3). ONE
/// round "?" button for a page's app bar (44 x 44 hit area, spoken name "About
/// this page") and ONE bottom-sheet frame (title, scrolling body, pinned
/// action row). Remembered recipients, Backup and restore and Delete data only
/// supply their texts.

/// The spoken name of the "?" button on a page's app bar.
const kAboutThisPage = 'About this page';

/// The Close button of a help sheet.
const kHelpClose = 'Close';

/// The round "?" (mock `.hq`): a 36 px circle inside a 44 x 44 hit area.
/// [expanded] non-null makes it a disclosure button (the Delete data sheet's
/// "?" shows or hides its extras): the circle fills with the primary colour
/// while the extras are shown.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.onPressed, this.label = kAboutThisPage, this.expanded});

  final VoidCallback onPressed;

  /// The spoken name.
  final String label;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final on = expanded ?? false;
    return Semantics(
      button: true,
      label: label,
      expanded: expanded,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: kMinTapTarget,
        height: kMinTapTarget,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? palette.primary : palette.card,
                border: on ? null : Border.all(color: palette.line, width: 1.5),
              ),
              child: Text(
                '?',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: on ? palette.onPrimary : palette.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame of a help sheet (mock `.hsheet`): a title (a screen-reader header
/// that also names the route, so opening the sheet reads the title), an
/// optional [headerAction] at the title's right, a scrolling body, and an
/// [actions] row PINNED under the scroll area so it stays on screen with a long
/// body, at large text and above the keyboard.
class HelpSheetFrame extends StatelessWidget {
  const HelpSheetFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.headerAction,
    this.bodyKey = const Key('helpSheetScroll'),
  });

  final String title;
  final List<Widget> body;
  final Widget? actions;
  final Widget? headerAction;
  final Key bodyKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // A modal sheet's route strips the top padding from MediaQuery, so the status bar height is read from the view.
    final statusBar = MediaQueryData.fromView(View.of(context)).padding.top;
    // Never taller than 92 percent of the screen, and never into the status bar: what is left above the keyboard minus the top safe area and a gap (R55).
    final maxH = math.min(MediaQuery.sizeOf(context).height * 0.92, MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - statusBar - 8);
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, -8))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                key: const Key('helpSheetTitle'),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25, color: palette.ink),
                              ),
                            ),
                          ),
                        ),
                        ?headerAction,
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      key: bodyKey,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < body.length; i++) ...[if (i > 0) const SizedBox(height: 10), body[i]],
                        ],
                      ),
                    ),
                  ),
                  if (actions != null)
                    Container(
                      key: const Key('helpSheetActions'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
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

/// One paragraph of a help sheet.
class HelpPara extends StatelessWidget {
  const HelpPara(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(text, style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.ink));
  }
}

/// The pinned Close button of a help sheet (a 44 px filled pill).
class HelpCloseButton extends StatelessWidget {
  const HelpCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FilledButton(
      key: const Key('helpSheetClose'),
      autofocus: true,
      onPressed: () => Navigator.of(context).pop(),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(kMinTapTarget),
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      child: const Text(kHelpClose),
    );
  }
}

/// Opens a page's help sheet: [title] and [paragraphs] only. The dimmed area,
/// Back, a swipe down and Close all close it.
Future<void> showHelpSheet(BuildContext context, {required String title, required List<String> paragraphs}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => HelpSheetFrame(
      title: title,
      body: [for (final p in paragraphs) HelpPara(p)],
      actions: const HelpCloseButton(),
    ),
  );
}

/// The app bar's "?" for a page whose help is just a title and paragraphs.
class HelpPageButton extends StatelessWidget {
  const HelpPageButton({super.key, required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return HelpButton(
      key: const Key('helpButton'),
      onPressed: () => showHelpSheet(context, title: title, paragraphs: paragraphs),
    );
  }
}
