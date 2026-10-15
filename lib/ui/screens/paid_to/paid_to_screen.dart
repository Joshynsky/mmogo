import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_counts.dart';
import '../../../domain/paid_to/paid_to_sheet.dart';
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
import 'not_recorded_line.dart';
import 'recipient_section.dart';
import 'recipient_sheet.dart';
import 'search_row.dart';
import 'type_pills.dart';

/// Paid to's coach-tour page id (the seen flag is `tour_seen_paid_to`).
const paidToTourId = 'paid_to';

/// Primary destination 4 of 5 (nav slot 3) — "Paid to" (T22), rebuilt in 0.1.2 S7b (PT1) to the
/// signed mock `paidto.html`: "who is my money going to?", grouped by recipient, never by category.
///  - a "Paid out" card with the All time / Year / Month pill (default this month): the total, the
///    Transaction cost, "to N recipients", "N payments", "+ M agents (cash out, not counted)" —
///    always the whole period; with the W pill open it reads "Withdrawn";
///  - Search (name, phone in any written form, account, agent number) + Filter (badge = active
///    filters) → the Filter & sort sheet (category scoped to the type; Amount, Times paid, Most
///    recent, Transaction cost; Reset; "Show N", applied on Show), with the active filters as chips;
///  - expand/collapse type pills All | SM | PB | BG | P | W with counts that follow the search and
///    the category;
///  - a section per type that has recipients (All = the top 3 + "See all N ›"), ranked rows with a
///    share bar (none for Most recent), and ONE muted "Not recorded" line per type for payments
///    with no captured receiver (not a recipient: no tap, in no count);
///  - a row tap opens the recipient sheet INSIDE Paid to; its "See these payments in Analytics"
///    button hands off to the Analytics recipient view on this period (all five types);
///  - no Cash, no Airtime.
/// Follows the phone's light/dark setting; pull to refresh = back to now.
///
/// Real data: `AnalyticsDao` (first transaction day, the period's itemized Send Money, Paybill,
/// Buy Goods, Pochi and Withdrawal rows); grouping and counts in `domain/paid_to/`.
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
      types: paidToAllTypes.toSet(),
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
            agentNumber: r.agentNumber,
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
      builder: (_) => PaidToFilterSheet(
        palette: palette,
        payments: _payments ?? const [],
        type: _tab,
        cls: _cls,
        sort: _sort,
        term: _search.text.trim(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _cls = result.$1;
      _sort = result.$2;
    });
  }

  /// A row tap: the recipient sheet inside Paid to (figures = the row's: the shown period and the
  /// row's category filter). Back, the scrim, Close and the X close it and focus returns to [row];
  /// "See these payments in Analytics" hands off after it closes.
  Future<void> _openRecipient(PaidToRecipient r, FocusNode row) async {
    final today = dateOnly(_now());
    final shown = _shown ?? _period;
    final data = paidToSheetData(
      r,
      range: shown.range(today: today, first: _first),
      month: shown.granularity == AnalyticsGranularity.month,
    );
    final goAnalytics = await showPaidToRecipientSheet(
      context,
      palette: AppPalette.of(context),
      recipient: r,
      data: data,
      periodWords: shown.words(today: today, first: _first).value,
    );
    if (!mounted) return;
    if (goAnalytics == true) {
      _openAnalytics(r);
    } else if (row.context != null) {
      row.requestFocus();
    }
  }

  /// The 0.1.1 hand-off (kept): the Analytics recipient view on this period's length and anchor,
  /// with the active category as its filter. Works for all five types (S7b: Pochi by phone key
  /// else name, Withdrawal by agent number else name).
  void _openAnalytics(PaidToRecipient r) {
    final today = dateOnly(_now());
    final period = analyticsPeriodForPaidTo(_shown ?? _period, today);
    final args = AnalyticsRouteArgs(
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
      CoachStep(target: _searchTourKey, text: 'Find someone, or use Filter & sort: amount, times paid or most recent.'),
      if (recipient != null && _firstRowTourKey.currentContext != null)
        CoachStep(
          target: _firstRowTourKey,
          text: 'Tap a name to see what you paid them, with a way on to every payment in Analytics.',
          onEnter: () => scrollIntoView(_firstRowTourKey),
          actionLabel: 'Take me there',
          onAction: () => _openAnalytics(recipient),
        ),
      if (_seeAllTourKey.currentContext != null)
        CoachStep(
          target: _seeAllTourKey,
          text: 'Top 3 per type are shown. See all lists everyone.',
          onEnter: () => scrollIntoView(_seeAllTourKey),
        ),
    ];
  }

  // §PAIDTO.SHELL.BUILD ---- build ------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final payments = _payments;
    return PrimaryScaffold(
      title: 'Paid to',
      activeIndex: PrimaryShellController.paidToIndex,
      followPhoneTheme: true,
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
          hero: paidToHero(payments, withdrawn: _tab == paidToWithdrawal),
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
      PaidToTypePills(
        palette: palette,
        counts: paidToCounts(payments, classification: _cls, term: _search.text.trim()),
        selected: _tab,
        onSelect: _selectTab,
      ),
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
        for (var i = 0; i < sections.length; i++) ...[
          // mock: the Not recorded line sits close under its card (margin-top -4 on an 11 px gap).
          if (i > 0) SizedBox(height: _isNotRecorded(sections[i]) ? 7 : 11),
          sections[i],
        ],
      ],
    );
  }

  int get _activeFilters => (_cls != null ? 1 : 0) + (_sort != PaidToSort.amount ? 1 : 0);

  // §PAIDTO.SHELL.LIST ---- the list (filters/sorts with shell state; a List<Widget> the body spaces) ----

  List<Widget> _list(List<PaidToPayment> payments, AppPalette palette) {
    final term = _search.text.trim();
    final list = paidToGroups(payments, type: _tab, classification: _cls, term: term);
    sortPaidTo(list, _sort);
    // Not recorded: one summary per type (hidden while searching; only for the open type pill).
    PaidToNotRecorded nrOf(String type) => _tab == null || _tab == type
        ? paidToNotRecorded(payments, type: type, classification: _cls, term: term)
        : const PaidToNotRecorded(0, 0, 0);
    if (list.isEmpty && !paidToAllTypes.any((t) => nrOf(t).count > 0)) {
      return [
        AppCard(
          palette: palette,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Text(
              term.isNotEmpty ? 'No one matches “$term”.' : 'No payments in this period.',
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
    // Placeholder wording (mock): shown when one recipient holds more than one stored phone form.
    if (list.any((g) => g.phones.length > 1)) {
      out.add(
        Padding(
          key: const Key('paidToMergeNote'),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'Some recipients were combined because their numbers match',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.mutedInk),
          ),
        ),
      );
    }
    var seeAllTagged = false; // only the first "See all" carries the tour key
    var firstSection = true;
    for (final type in paidToAllTypes) {
      final part = list.where((g) => g.sourceType == type).toList();
      final nr = nrOf(type);
      Widget nrLine({required bool withType}) => PaidToNotRecordedLine(
        key: Key('paidToNotRecorded-$type'),
        palette: palette,
        type: type,
        summary: nr,
        withType: withType,
      );
      if (part.isEmpty) {
        // mock: a type without recipients still shows its Not recorded line, with the type name.
        if (nr.count > 0) out.add(nrLine(withType: true));
        continue;
      }
      final section = PaidToSection(type, part);
      final shown = overview ? part.take(3).toList() : part;
      final hasSeeAll = overview && part.length > 3;
      if (firstSection) _tourRecipient = shown.first;
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
          firstRowTourKey: firstSection ? _firstRowTourKey : null,
        ),
      );
      firstSection = false;
      if (nr.count > 0) out.add(nrLine(withType: false));
    }
    return out;
  }

  /// A body item is a Not recorded line (it sits closer under its card).
  static bool _isNotRecorded(Widget w) => w is Padding && w.child is PaidToNotRecordedLine;
}
