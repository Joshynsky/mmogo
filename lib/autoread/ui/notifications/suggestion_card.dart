/// §AUTOREAD.SUGGESTION_CARD - the offer "Ask first next time?" and the Suggestions section.
/// Today's card, top to bottom: title, body, small "Not now" (far left), one filled confirm "Ask first"
/// (far right). 0.2.2 (U2, mock offer-a): while `autoRecordUi`, for a kind that can hold Auto-record and a
/// known category, the card is "Auto-record {name}?" with two big buttons (Ask me first, Auto-record) and
/// "Not now" on its own line at the end edge (RTL-safe). Paybill (D2), flag off or no category: today's
/// card exactly. Hidden while there is no offer. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../logic/phone_mask.dart';
import '../../rules/rule_engine.dart';
import '../../rules/rule_model.dart';
import '../levels/hard_rule_copy.dart';
import '../levels/hard_rule_ports.dart';
import '../row_parts.dart';
import 'notifications_rule_copy.dart';
import 'rule_pill.dart';

/// The person as the offer names them. F2: two people with one name are told apart by the masked number
/// (Send Money only).
String offerWho(Offer o) => o.type == ReceiverType.sendMoney ? nameWithMask(o.name, o.key) : o.name;

/// Whether the offer card shows the Auto-record choice: the UI flag is on, the kind can hold Auto-record
/// (D2: Paybill cannot) and the category has a name (the body and the confirm dialog both say it).
bool offersAutoRecord(Offer o, String? categoryName) =>
    autoRecordUi && canHoldAutoRecord(o.type) && categoryName != null;

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.offer,
    required this.categoryName,
    required this.onNotNow,
    required this.onConfirm,
    this.onAutoRecord,
    this.times,
  });
  final Offer offer;

  /// Name of [Offer.categoryId]; null when unknown.
  final String? categoryName;
  final VoidCallback onNotNow;
  final VoidCallback onConfirm;

  /// The Auto-record button. Null: today's card (no Auto-record choice).
  final VoidCallback? onAutoRecord;

  /// The N of the Auto-record body (the Settings "Suggest after" number). Null: the offer's own run.
  final int? times;

  @override
  Widget build(BuildContext context) {
    final cat = categoryName;
    final auto = onAutoRecord;
    if (auto != null && cat != null && offersAutoRecord(offer, cat)) return _autoCard(context, cat, auto);
    return _todayCard(context, cat);
  }

  Widget _frame(BuildContext context, {required String label, required List<Widget> children}) {
    final p = AppPalette.of(context);
    return Semantics(
      container: true,
      label: label,
      child: Container(
        key: Key('suggestion-${offer.type.code}-${offer.key}'),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _texts(BuildContext context, String title, String body) {
    final p = AppPalette.of(context);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: p.ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(color: p.mutedInk, fontSize: 12.5, height: 1.35)),
        ],
      ),
    );
  }

  Widget _notNow(BuildContext context, String label) => TextButton(
        key: const Key('suggestion-not-now'),
        onPressed: onNotNow,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 4)),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.of(context).mutedInk)),
      );

  /// Today's card (0.2.1/0.2.2 before U2), unchanged.
  Widget _todayCard(BuildContext context, String? cat) {
    final who = offerWho(offer);
    final body = cat == null ? suggestionBodyNoCat(who, offer.run) : suggestionBody(who, cat, offer.run);
    return _frame(
      context,
      label: '$kSuggestionTitle $body',
      children: [
        _texts(context, kSuggestionTitle, body),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: _notNow(context, kSuggestionNotNow)),
        Align(
          alignment: Alignment.centerRight,
          child: RulePill(
            key: const Key('suggestion-confirm'),
            label: kSuggestionConfirm,
            spoken: '$kSuggestionConfirm: $who',
            fill: true,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }

  /// Mock offer-a: two big buttons in one row (Ask me first, then Auto-record filled), Not now alone on
  /// the next line at the end edge.
  Widget _autoCard(BuildContext context, String cat, VoidCallback auto) {
    final who = offerWho(offer);
    final title = hardOfferTitle(who);
    final body = hardOfferBody(who, cat, times ?? offer.run);
    return _frame(
      context,
      label: '$title $body',
      children: [
        _texts(context, title, body),
        const SizedBox(height: 10),
        Row(
          key: const Key('suggestion-choices'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RulePill(
                key: const Key('suggestion-confirm'),
                label: kHardOfferAskFirst,
                spoken: '$kHardOfferAskFirst: $who',
                onTap: onConfirm,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RulePill(
                key: const Key('suggestion-auto'),
                label: kHardOfferAutoRecord,
                spoken: '$kHardOfferAutoRecord: $who',
                fill: true,
                onTap: auto,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(alignment: AlignmentDirectional.centerEnd, child: _notNow(context, kHardOfferNotNow)),
      ],
    );
  }
}

/// The Suggestions section (0.2.2, F10): heading with the total, ONE card (the first offer) and, when more
/// wait, a quiet "n more" line. The next offer shows when this one is answered. Nothing when [offers] is empty.
class SuggestionsSection extends StatelessWidget {
  const SuggestionsSection({
    super.key,
    required this.offers,
    required this.categoryName,
    required this.onNotNow,
    required this.onConfirm,
    this.onAutoRecord,
    this.times,
  });
  final List<Offer> offers;
  final String? Function(int categoryId) categoryName;
  final void Function(Offer offer) onNotNow;
  final void Function(Offer offer) onConfirm;

  /// Auto-record on the card (U2). Null: today's card.
  final void Function(Offer offer)? onAutoRecord;

  /// The Settings "Suggest after" number for the Auto-record body.
  final int? times;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    final o = offers.first;
    final more = offers.length - 1;
    final auto = onAutoRecord;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('$kHeadingSuggestions (${offers.length})'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SuggestionCard(
            offer: o,
            categoryName: categoryName(o.categoryId),
            onNotNow: () => onNotNow(o),
            onConfirm: () => onConfirm(o),
            onAutoRecord: auto == null ? null : () => auto(o),
            times: times,
          ),
        ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              suggestionsMoreLine(more),
              key: const Key('suggestions-more'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.of(context).mutedInk),
            ),
          ),
      ],
    );
  }
}
