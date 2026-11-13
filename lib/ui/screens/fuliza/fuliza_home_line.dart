import 'package:flutter/material.dart';

import '../../../domain/fuliza/fuliza_home_rows.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';

/// §FULIZA.HOME_LINE: one tappable block inside the main card, under Transaction cost: up to two
/// label / figure rows and one chevron (see `fulizaHomeRows` for when each row exists). The whole block
/// is the tap target (at least 44 high) and opens the Fuliza page. Labels wrap at large text sizes; the
/// figures stay on one line. The Home total, the type bars and Transaction cost never include Fuliza.
/// WORDING-DRAFT: the row labels (in `fuliza_home_rows.dart`) and the spoken "Open details".
class FulizaHomeLine extends StatelessWidget {
  const FulizaHomeLine({super.key, required this.palette, required this.rows, required this.onTap});

  final AppPalette palette;
  final FulizaHomeRows rows;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: '${rows.spoken}. Open details',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('homeFulizaLine'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rows.owing != null) _row(const Key('homeFulizaOwing'), rows.owing!, p),
                      if (rows.cost != null) _row(const Key('homeFulizaCost'), rows.cost!, p),
                    ],
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Key key, FulizaHomeRow r, AppPalette p) {
    final style = TextStyle(fontSize: 12, fontFeatures: tabularFigures, color: p.mutedInk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(r.label, key: key, style: style)),
          if (r.value != null) ...[
            const SizedBox(width: 8),
            Text(
              r.value!,
              key: Key('${(key as ValueKey<String>).value}Value'),
              softWrap: false,
              style: style.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
