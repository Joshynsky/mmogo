import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette_scope.dart';
import 'settings_widgets.dart';

/// Settings "Appearance" section: the colour-palette card. [tourKey] is the
/// coach-tour anchor owned by the Settings shell.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.palette, required this.tourKey});

  final AppPalette palette;
  final GlobalKey tourKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel('Appearance', palette: palette),
        KeyedSubtree(
          key: tourKey,
          child: SettingsCard(
            palette: palette,
            child: _PaletteGroup(
              currentPaletteId: AppPaletteScope.of(context).value,
              palette: palette,
              onSelect: (id) => AppPaletteScope.of(context).select(id),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Colour palette" head + the 3-tile radio group (mock `.shead` +
/// `.palgrid`).
class _PaletteGroup extends StatelessWidget {
  const _PaletteGroup({required this.currentPaletteId, required this.palette, required this.onSelect});

  final String currentPaletteId;
  final AppPalette palette;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Colour palette', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
              const SizedBox(height: 3),
              Text(
                'Recolours the whole app. Light or dark follows your phone.',
                style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Semantics(
            container: true,
            label: 'Colour palette',
            child: Row(
              children: [
                for (final (i, set) in AppPalettes.all.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PaletteTile(
                      set: set,
                      brightness: palette.brightness,
                      accent: palette,
                      selected: set.id == currentPaletteId,
                      onTap: () => onSelect(set.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One palette radio tile (mock `.pal`): a mini preview (the primary strip
/// + page background + the 4 type-colour bars), the name, and a check on
/// the selected one. The preview always shows the OPTION's own colours at
/// the phone's current brightness; the selected border/check use the
/// currently ACTIVE palette's primary ([accent]), same as the mock's
/// `var(--primary)` (set by whichever palette is applied app-wide).
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.set,
    required this.brightness,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppPaletteSet set;
  final Brightness brightness;
  final AppPalette accent;
  final bool selected;
  final VoidCallback onTap;

  static const _barHeights = [0.70, 0.45, 0.30, 0.55];

  @override
  Widget build(BuildContext context) {
    final preview = set.forBrightness(brightness);
    final typeColors = [preview.typeSendMoney, preview.typePaybill, preview.typeBuyGoods, preview.typeCash];
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${set.name}${selected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Material(
        color: preview.background,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: InkWell(
          key: Key('paletteTile-${set.id}'),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(color: selected ? accent.primary : accent.line, width: 2),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(9)),
                      child: SizedBox(
                        height: 46,
                        child: Column(
                          children: [
                            Container(height: 14, color: preview.primary),
                            Expanded(
                              child: Container(
                                color: preview.background,
                                padding: const EdgeInsets.fromLTRB(5, 4, 5, 0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (final (i, c) in typeColors.indexed) ...[
                                      if (i > 0) const SizedBox(width: 3),
                                      Expanded(
                                        child: FractionallySizedBox(
                                          heightFactor: _barHeights[i],
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: c,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      set.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: preview.ink),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: accent.primary, shape: BoxShape.circle),
                      child: Icon(Icons.check, size: 12, color: accent.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
