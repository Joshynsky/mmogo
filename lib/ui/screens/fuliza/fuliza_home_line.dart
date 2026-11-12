import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/fuliza/fuliza_page_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';

/// §FULIZA.HOME_LINE — 0.2.0 S9, Home variant V3 (PM 03-11-2026): ONE line inside the main card, under
/// Transaction cost: "Fuliza · Owing Ksh X" on the left, the label "Details" and a visible chevron in the
/// primary colour on the right. The whole line is the tap target (at least 44 high) and opens the Fuliza
/// page. It only exists when there is Fuliza data; the Home total, the type bars and Transaction cost never
/// include Fuliza (a loan is not spending).
/// WORDING-DRAFT: "Fuliza · Owing Ksh X", "Fuliza · Owing about Ksh X", "Fuliza · Owing unknown",
/// "Fuliza · Nothing owed", "Details".
class FulizaHomeLine extends StatelessWidget {
  const FulizaHomeLine({super.key, required this.palette, required this.data, required this.onTap});

  final AppPalette palette;
  final FulizaPageData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final label = fulizaHomeLineLabel(data, formatKsh);
    return Semantics(
      button: true,
      label: '${label.replaceFirst(' · ', ', ')}. Open details',
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
                child: Text(
                  label,
                  key: const Key('homeFulizaText'),
                  style: TextStyle(fontSize: 12, fontFeatures: tabularFigures, color: p.mutedInk),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Details',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.primary),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}
