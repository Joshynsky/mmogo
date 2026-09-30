import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../shell/primary_scaffold.dart';
import '../../shell/primary_shell.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/coach_tour.dart';
import '../../widgets/period_pill.dart';
import '../analytics_screen.dart' show AnalyticsRouteArgs;
import 'filter_sheet.dart';
import 'hero_card.dart';
import 'recipient_section.dart';
import 'search_row.dart';
import 'type_pills.dart';

/// Paid to's coach-tour page id (the seen flag is `tour_seen_paid_to`).
const paidToTourId = 'paid_to';

/// Primary destination 4 of 5 (nav slot 3) — T22's "Paid to" (formerly
/// Parties, T15), built to the PM-locked prototype v12
/// (the approved onboarding mock's Paid to screen):
/// "who is my money going to?", grouped by recipient, never by category.
///  - a "Paid out" card with the All time / Year / Month pill (default this
///    month): the period total, "to N recipients", "M payments" — always the
///    whole period, never narrowed by the type pill or the filter;
///  - Search + Filter (badge = active filters) → the Filter & sort sheet
///    (category scoped to the type, with counts; Amount / Times paid / Most
///    recent; Reset; "Show N recipients", applied on Show), with the active
///    filters as removable chips;
///  - type pills All | Send Money | Paybill | Buy Goods with recipient counts;
///  - a section per type (All = the top 3 + "See all N ›"), ranked rows with
///    a share bar (none for Most recent);
///  - unnamed payments (no receiver captured) grouped by classification, in
///    italics with a muted tile — the T15 rule: never excluded;
///  - no Cash; a tap opens the Analytics recipient view on this period.
/// Follows the phone's light/dark setting; pull to refresh = back to now.
///
/// Real data: `AnalyticsDao` (first transaction day, the period's itemized
/// Send Money / Paybill / Buy Goods rows); grouping in
/// `domain/paid_to/paid_to.dart`.
class PaidToScreen extends StatefulWidget {
  const PaidToScreen({super.key, this.db, this.clock});

  /// Test seam: the database (a real sqflite_common_ffi `Database` hangs
  /// inside `testWidgets`). `null` = the app's real database.
  final Database? db;

  /// Test seam: "now".
  final DateTime Function()? clock;

  @override
  State<PaidToScreen> createState() => _PaidToScreenState();
}

class _PaidToScreenState extends State<PaidToScreen> with PrimaryTabRefresh<PaidToScreen> {
  // §PAIDTO.SHELL.STATE ---- state ---------------------------------------------------
  late AnalyticsPeriod _period = AnalyticsPeriod.month(_now());

  /// The loaded period's payments (the period they belong to is [_shown]).
  List<PaidToPayment>? _payments;
  AnalyticsPeriod? _shown;
  DateTime? _first;
  int _loadSeq = 0;

  /// `null` = All.
  String? _tab;
  String? _cls;
  PaidToSort _sort = PaidToSort.amount;
  final _search = TextEditingController();

  final _scroll = ScrollController();
  final _granKey = GlobalKey();
  final _valueKey = GlobalKey();

  // Coach-tour anchors (see §PAIDTO.SHELL.TOUR).
  final _searchTourKey = GlobalKey();
  final _firstRowTourKey = GlobalKey();
  final _seeAllTourKey = GlobalKey();
  PaidToRecipient? _tourRecipient;
  bool _tourOffered = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // F5: back on the tab, re-query; period, filters, search and scroll stay.
  @override
  int get primaryTabIndex => PrimaryShellController.paidToIndex;

  @override
  void onPrimaryTabShown() {
    _load();
    // Back from a tour's "Take me there": pick the tour up where it paused.
    // (This also fires for data changes while another tab is showing.)
    if (_tourOffered && primaryShell?.index.value == primaryTabIndex) _offerTour();
  }

  // §PAIDTO.SHELL.LOAD ---- load, period ---------------------------------------------

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final period = _period;
    final db = widget.db ?? await AppDatabase.instance.database;
    final today = dateOnly(_now());
    final firstAt = await AnalyticsDao.firstOccurredAt(db);
    final first = firstAt == null ? null : dateOnly(firstAt);
    final (startMs, endMs) = period.range(today: today, first: first).bounds;
    final rows = await AnalyticsDao.itemizedTransactions(
      db,
      startMs: startMs,
      endMs: endMs,
      types: paidToTypes.toSet(),
    );
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _first = first;
      _shown = period;
      _payments = [
        for (final r in rows)
          PaidToPayment(
            sourceType: r.sourceType,
            amountCents: r.amountCents,
            feeCents: r.transactionCostCents ?? 0,
            occurredAt: r.occurredAt,
            classificationName: r.classificationName,
            label: r.counterpartyLabel,
            phone: r.counterpartyPhone,
            account: r.paybillAccountNumber,
          ),
      ];
    });
    // First tour: once, when there is a list to point at.
    if (!_tourOffered && _payments!.isNotEmpty) {
      _tourOffered = true;
      _offerTour();
    }
  }

  /// Shows the tour (or its unfinished rest) once the frame has painted.
  void _offerTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: paidToTourId, steps: _tourSteps());
    });
  }

  void _setPeriod(AnalyticsPeriod p) {
    setState(() => _period = p);
    _load();
  }

  /// Pull to refresh = back to now: the same length, the current one; the
  /// search is cleared; type, category and sort stay (mock PT_API).
  Future<void> _backToNow() async {
    _search.clear();
    setState(() => _period = paidToPeriodNow(_period.granularity, dateOnly(_now())));
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load();
  }

  Future<void> _openGranularityMenu() async {
    final today = dateOnly(_now());
    final picked = await showPeriodMenu<AnalyticsGranularity>(
      context,
      anchor: _granKey,
      palette: AppPalette.of(context),
      items: [for (final (g, label) in paidToGranularities) (label, '', _period.granularity == g, g)],
    );
    if (picked == null || !mounted) return;
    _setPeriod(paidToPeriodNow(picked, today));
  }

  Future<void> _openValueMenu() async {
    final today = dateOnly(_now());
    final options = _period.options(today: today, first: _first);
    if (options.isEmpty) return; // All time
    final picked = await showPeriodMenu<AnalyticsPeriod>(
      context,
      anchor: _valueKey,
      palette: AppPalette.of(context),
      items: [for (final o in options) (o.label, o.note, o.selected, o.period)],
    );
    if (picked == null || !mounted) return;
    _setPeriod(picked);
  }

  // §PAIDTO.SHELL.ACTIONS ---- tab, see-all, filter sheet, open recipient ----------

  /// A type pill: keeps the category if that type has it, else drops it.
  void _selectTab(String? type) {
    final payments = _payments ?? const [];
    setState(() {
      _tab = type;
      if (_cls != null && !paidToCategories(payments, type: type).any((c) => c.$1 == _cls)) _cls = null;
    });
  }

  /// "See all N ›": that type's pill (the category is dropped, as in the mock).
  void _seeAll(String type) {
    setState(() {
      _tab = type;
      _cls = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openFilterSheet() async {
    final palette = AppPalette.of(context);
    final result = await showModalBottomSheet<(String?, PaidToSort)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) =>
          PaidToFilterSheet(palette: palette, payments: _payments ?? const [], type: _tab, cls: _cls, sort: _sort),
    );
    if (result == null || !mounted) return;
    setState(() {
      _cls = result.$1;
      _sort = result.$2;
    });
  }

  void _openRecipient(PaidToRecipient r) {
    final today = dateOnly(_now());
    final period = analyticsPeriodForPaidTo(_shown ?? _period, today);
    final args = r.isUnnamed
        ? AnalyticsRouteArgs(type: r.sourceType, period: period, classification: r.classificationName)
        : AnalyticsRouteArgs(
            type: r.sourceType,
            partyKey: r.partyKey,
            partyName: r.name,
            period: period,
            classification: _cls,
          );
    final shell = primaryShell;
    if (shell != null) {
      shell.openAnalytics(args);
      return;
    }
    Navigator.of(context).pushNamed(Routes.analytics, arguments: args);
  }

  // §PAIDTO.SHELL.TOUR ---- coach tour --------------------------------------------

  /// Search + Filter, then (when the list has them) a recipient row and the
  /// first "See all". Looks at what is built right now.
  List<CoachStep> _tourSteps() {
    final recipient = _tourRecipient;
    return [
      CoachStep(
        target: _searchTourKey,
        text: 'Find someone, or use Filter & sort: amount, times paid or most recent.',
      ),
      if (recipient != null && _firstRowTourKey.currentContext != null)
        CoachStep(
          target: _firstRowTourKey,
          text: 'Tap a name to see every payment to them in Analytics.',
          onEnter: () => scrollIntoView(_firstRowTourKey),
          actionLabel: 'Take me there',
          onAction: () => _openRecipient(recipient),
        ),
      if (_seeAllTourKey.currentContext != null)
        CoachStep(
          target: _seeAllTourKey,
          text: 'Top 3 per type are shown. See all lists everyone.',
          onEnter: () => scrollIntoView(_seeAllTourKey),
        ),
    ];
  }

  void _replayTour() => CoachTour.start(context, pageId: paidToTourId, steps: _tourSteps());

  // §PAIDTO.SHELL.BUILD ---- build ------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final payments = _payments;
    return PrimaryScaffold(
      title: 'Paid to',
      activeIndex: PrimaryShellController.paidToIndex,
      followPhoneTheme: true,
      onHelp: payments == null ? null : _replayTour,
      body: payments == null
          ? Center(child: CircularProgressIndicator(color: palette.primary))
          : RefreshIndicator(
              key: const Key('paidToRefresh'),
              color: palette.primary,
              backgroundColor: palette.card,
              onRefresh: _backToNow,
              child: SingleChildScrollView(
                key: const Key('paidToScroll'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 40),
                child: _body(payments, palette),
              ),
            ),
    );
  }

  Widget _body(List<PaidToPayment> payments, AppPalette palette) {
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: w);
    final shown = _shown ?? _period;
    final sections = <Widget>[
      pad(
        PaidToHeroCard(
          palette: palette,
          payments: payments,
          shown: shown,
          first: _first,
          today: dateOnly(_now()),
          granKey: _granKey,
          valueKey: _valueKey,
          onGranularity: _openGranularityMenu,
          onValue: shown.granularity == AnalyticsGranularity.all ? null : _openValueMenu,
        ),
      ),
      pad(
        KeyedSubtree(
          key: _searchTourKey,
          child: PaidToSearchRow(
            palette: palette,
            controller: _search,
            activeFilters: _activeFilters,
            onChanged: () => setState(() {}),
            onFilter: _openFilterSheet,
          ),
        ),
      ),
      PaidToTypePills(palette: palette, payments: payments, selected: _tab, onSelect: _selectTab),
      if (_cls != null || _sort != PaidToSort.amount)
        pad(
          PaidToActiveChips(
            palette: palette,
            cls: _cls,
            sort: _sort,
            onClearCategory: () => setState(() => _cls = null),
            onClearSort: () => setState(() => _sort = PaidToSort.amount),
          ),
        ),
      ..._list(payments, palette).map(pad),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[if (i > 0) const SizedBox(height: 11), sections[i]],
      ],
    );
  }

  int get _activeFilters => (_cls != null ? 1 : 0) + (_sort != PaidToSort.amount ? 1 : 0);

  // §PAIDTO.SHELL.LIST ---- the list (filters/sorts with shell state; a List<Widget> the body spaces) ----

  List<Widget> _list(List<PaidToPayment> payments, AppPalette palette) {
    final term = _search.text.trim().toLowerCase();
    final list = groupPaidTo(
      payments,
      classification: _cls,
    ).where((g) => (_tab == null || g.sourceType == _tab) && (term.isEmpty || g.searchText.contains(term))).toList();
    sortPaidTo(list, _sort);
    if (list.isEmpty) {
      return [
        AppCard(
          palette: palette,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Text(
              term.isNotEmpty ? 'No one matches “${_search.text.trim()}”.' : 'No payments in this period.',
              key: const Key('paidToEmpty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: palette.mutedInk),
            ),
          ),
        ),
      ];
    }
    final overview = _tab == null;
    final ranked = _sort != PaidToSort.recent;
    final out = <Widget>[];
    var seeAllTagged = false; // only the first "See all" carries the tour key
    for (final type in paidToTypes) {
      final part = list.where((g) => g.sourceType == type).toList();
      if (part.isEmpty) continue;
      final section = PaidToSection(type, part);
      final shown = overview ? part.take(3).toList() : part;
      final first = out.isEmpty;
      final hasSeeAll = overview && part.length > 3;
      if (first) _tourRecipient = shown.first;
      out.add(
        PaidToSectionHeader(
          palette: palette,
          section: section,
          seeAll: hasSeeAll,
          onSeeAll: () => _seeAll(type),
          seeAllTourKey: hasSeeAll && !seeAllTagged ? _seeAllTourKey : null,
        ),
      );
      if (hasSeeAll) seeAllTagged = true;
      out.add(
        PaidToListCard(
          palette: palette,
          shown: shown,
          ranked: ranked,
          sort: _sort,
          today: dateOnly(_now()),
          onOpen: _openRecipient,
          firstRowTourKey: first ? _firstRowTourKey : null,
        ),
      );
    }
    return out;
  }
}
