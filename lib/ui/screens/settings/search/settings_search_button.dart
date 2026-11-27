import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/tap_target.dart';
import 'settings_search_index.dart';

/// The title bar's search icon: same round outline as the "?" help button (36 px circle in a 44 px hit area).
class SettingsSearchButton extends StatelessWidget {
  const SettingsSearchButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: kSettingsSearchLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: kMinTapTarget,
        height: kMinTapTarget,
        child: InkWell(
          key: const Key('settingsSearchButton'),
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.card, border: Border.all(color: palette.line, width: 1.5)),
              child: Icon(Icons.search, size: 20, color: palette.ink),
            ),
          ),
        ),
      ),
    );
  }
}
