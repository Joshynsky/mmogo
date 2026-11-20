/// §AUTOREAD.SUGGESTION_CARD - the offer "Ask first next time?" and the Suggestions section.
/// Top to bottom: title, body, small "Not now" (far left), one filled confirm "Ask first"
/// (far right). Hidden while there is no offer. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_engine.dart';
import '../row_parts.dart';
import 'notifications_rule_copy.dart';
import 'rule_pill.dart';

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({super.key, required this.offer, required this.categoryName, required this.onNotNow, required this.onConfirm});
  final Offer offer;

  /// Name of [Offer.categoryId]; null when unknown.
  final String? categoryName;
  final VoidCallback onNotNow;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final cat = categoryName;
    final body = cat == null ? suggestionBodyNoCat(offer.name, offer.run) : suggestionBody(offer.name, cat, offer.run);
    return Semantics(
      container: true,
      label: '$kSuggestionTitle $body',
      child: Container(
        key: Key('suggestion-${offer.type.code}-${offer.key}'),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kSuggestionTitle, style: TextStyle(color: p.ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(body, style: TextStyle(color: p.mutedInk, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('suggestion-not-now'),
                onPressed: onNotNow,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 4)),
                child: Text(kSuggestionNotNow, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.mutedInk)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: RulePill(
                key: const Key('suggestion-confirm'),
                label: kSuggestionConfirm,
                spoken: '$kSuggestionConfirm: ${offer.name}',
                fill: true,
                onTap: onConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Suggestions section: heading with the count, one card per offer. Nothing when [offers] is empty.
class SuggestionsSection extends StatelessWidget {
  const SuggestionsSection({super.key, required this.offers, required this.categoryName, required this.onNotNow, required this.onConfirm});
  final List<Offer> offers;
  final String? Function(int categoryId) categoryName;
  final void Function(Offer offer) onNotNow;
  final void Function(Offer offer) onConfirm;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('$kHeadingSuggestions (${offers.length})'),
        for (final o in offers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SuggestionCard(
              offer: o,
              categoryName: categoryName(o.categoryId),
              onNotNow: () => onNotNow(o),
              onConfirm: () => onConfirm(o),
            ),
          ),
      ],
    );
  }
}
