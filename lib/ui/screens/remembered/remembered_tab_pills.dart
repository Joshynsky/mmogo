import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §SCREEN.REMEMBERED.TAB_PILLS: the two-tab pill bar on the Remembered page
/// (at least 44 px tall; a label wraps at large text instead of overflowing).
class RememberedTabPills extends StatelessWidget {
  const RememberedTabPills({
    super.key,
    required this.palette,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final AppPalette palette;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  label: label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: Key('rememberedTab$i'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelect(i),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: i == selected ? palette.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: i == selected ? palette.primary : palette.line, width: 1.5),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: i == selected ? palette.onPrimary : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
