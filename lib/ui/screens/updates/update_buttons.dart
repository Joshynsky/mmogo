import 'package:flutter/material.dart';

import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';

/// The Updates page's button area: "Check for updates now" alone, or, when an
/// update is waiting, the check button beside a filled "Update" button that
/// opens the mmogo page for the build the user has.
class UpdateButtons extends StatelessWidget {
  const UpdateButtons({
    super.key,
    required this.palette,
    required this.checking,
    required this.updateAvailable,
    required this.onCheck,
    required this.onUpdate,
  });

  final AppPalette palette;
  final bool checking;
  final bool updateAvailable;
  final VoidCallback onCheck;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final check = SizedBox(
      height: 44, // the hit-area floor
      child: OutlinedButton.icon(
        key: const Key('checkNowButton'),
        onPressed: checking ? null : onCheck,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(checking ? kUpdatesCheckingLabel : kUpdatesCheckNowLabel),
        style: OutlinedButton.styleFrom(foregroundColor: palette.primary),
      ),
    );
    if (!updateAvailable) return check;
    // Side by side (PM 20-11-2026): the longer check label gets more room.
    return Row(
      children: [
        Expanded(flex: 3, child: check),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 44,
            child: FilledButton.icon(
              key: const Key('updateDownloadButton'),
              onPressed: onUpdate,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(kUpdatesDownloadLabel),
              style: FilledButton.styleFrom(backgroundColor: palette.primary),
            ),
          ),
        ),
      ],
    );
  }
}
