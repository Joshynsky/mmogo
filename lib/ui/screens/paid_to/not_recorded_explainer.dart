import 'package:flutter/material.dart';

import '../../copy/settings_copy.dart' show kCaptureReceiverLabel;
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';

/// §PAIDTO.NOT_RECORDED_EXPLAINER — 0.2.1 #4: what the "Receiver not saved" line means, in a small
/// sheet, with a way to the "Record receiver details" switch in Settings. Pops `true` when "Open
/// Settings" was chosen (the caller opens Settings and outlines the switch), else `null`.
/// WORDING-DRAFT: every string below.
const kNotRecordedTitle = 'Why is the receiver not saved?';
const kNotRecordedBody =
    'These payments were saved without who they went to, so they cannot be listed under a name. '
    'mmogo keeps a receiver’s name and number only while "$kCaptureReceiverLabel" is on. '
    'Turning it on affects new payments only. Payments already saved stay as they are.';
const kNotRecordedOpenSettings = 'Open Settings';
const kNotRecordedClose = 'Close';

Future<bool?> showPaidToNotRecordedExplainer(BuildContext context, {required AppPalette palette}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _NotRecordedExplainer(palette: palette),
  );
}

class _NotRecordedExplainer extends StatelessWidget {
  const _NotRecordedExplainer({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget button(Key key, String text, Color bg, Color fg, bool result) => Expanded(
      child: FilledButton(
        key: key,
        onPressed: () => Navigator.of(context).pop(result ? true : null),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
        ),
        child: Text(text, maxLines: 2, textAlign: TextAlign.center),
      ),
    );
    return BottomSheetShell(
      palette: p,
      children: [
        Text(
          kNotRecordedTitle,
          key: const Key('paidToNotRecordedTitle'),
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink),
        ),
        Text(
          kNotRecordedBody,
          key: const Key('paidToNotRecordedBody'),
          style: TextStyle(fontSize: 13, height: 1.45, color: p.softInk),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              button(const Key('paidToNotRecordedSettings'), kNotRecordedOpenSettings, p.primary, p.onPrimary, true),
              const SizedBox(width: 8),
              button(const Key('paidToNotRecordedClose'), kNotRecordedClose, p.track, p.ink, false),
            ],
          ),
        ),
      ],
    );
  }
}
