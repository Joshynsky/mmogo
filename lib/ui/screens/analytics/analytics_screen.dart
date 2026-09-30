import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../shell/primary_scaffold.dart';
import '../../shell/primary_shell.dart';
import '../../theme/app_colors.dart';
import '../../widgets/coach_tour.dart';
import '../../widgets/period_pill.dart';
import 'analytics_view.dart';
import 'chart_card.dart';
import 'custom_dates_sheet.dart';
import 'edit_sheet.dart';
import 'format.dart';
import 'hero_card.dart';
import 'party_card.dart';
import 'route_args.dart';
import 'sheet_parts.dart';
import 'toast.dart';
import 'tour.dart';
import 'transaction_list.dart';
import 'type_breakdown.dart';
import 'where_breakdown.dart';

/// Primary destination 3 of 5 — T21's reworked Analytics, built to the
/// approved analytics mock (v4, view B, "Claude's take") and its place in
/// the app flow in the onboarding mock (v7):
///  - a total card with the two-part period pill and the Custom sheet;
///  - a period-aware stacked bar chart (swipe / ‹ › / bar tap-through);
///  - By type | Where it went (one filter at a time);
///  - the transactions grouped by day, swipe right = edit, left = delete
///    with Undo; tapping a row opens the edit form, which also deletes;
///  - pull to refresh = "back to now".
/// Follows the phone's light/dark setting (`followPhoneTheme`).
///
/// Real data: `AnalyticsDao` (first transaction day, itemized rows),
/// `TransactionDao` (update / softDelete / restore).
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.db, this.clock});

  /// Test seam: the database (a real sqflite_common_ffi `Database` hangs
  /// inside `testWidgets`, so widget tests pass a fake). `null` = the app's
  /// real database.
  final Database? db;

  /// Test seam: "now".
  final DateTime Function()? clock;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with PrimaryTabRefresh<AnalyticsScreen> {
  // §ANALYTICS.SHELL.STATE — every field the screen holds.
  bool _argsResolved = false;

  AnalyticsBeforeParty? _beforeParty;

  /// Where to scroll once the next load has laid out (restoring a place).
  double? _pendingScroll;

  /// A hand-off is being applied; the tab-shown refresh leaves it alone.
  bool _handoffBusy = false;
  AnalyticsRequest? _lastRequest;

  late AnalyticsPeriod _period;
  String? _partyType;
  String? _partyKey;
  String? _partyName;

  bool get _isParty => _partyType != null && _partyKey != null;

  /// Both can be active together (T26 "yes allow type and category"): a
  /// type code and/or a classification name; the transactions list filters
  /// on the AND of the two that are set.
  String? _typeFilter;
  String? _classFilter;

  bool _whereTab = false;
  bool _showAllClasses = false;

  AnalyticsView? _view;
  int _loadSeq = 0;

  final _scroll = ScrollController();
  final _granKey = GlobalKey();
  final _valueKey = GlobalKey();
  final _chartTourKey = GlobalKey();
  final _breakdownTourKey = GlobalKey();
  bool _tourOffered = false;

  final Map<int, GlobalKey> _rowKeys = {};
  int? _pendingHighlightId;
  int? _highlightedId;
  Timer? _highlightTimer;

  int? _openRowId;

  String? _toastMessage;
  int? _undoId;
  Timer? _toastTimer;

  late final AppLifecycleListener _lifecycle;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Future<Database> _db() async => widget.db ?? await AppDatabase.instance.database;

  @override
  void initState() {
    super.initState();
    _period = AnalyticsPeriod.lastSevenDays(_now());
    // Back from the background: fresh data, but the period, filters and
    // scroll position stay where the user was (T21 brief, binding add-on).
    _lifecycle = AppLifecycleListener(onResume: _load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsResolved) return;
    _argsResolved = true;
    final shell = primaryShell;
    shell?.analyticsRequest.addListener(_onRequest);
    shell?.periodLength.addListener(_onSharedLength);
    // F6: a Home length change made before Analytics was first built.
    final last = shell?.periodLength.value;
    if (last != null && !last.fromAnalytics) _period = analyticsPeriodForHome(last.length, dateOnly(_now()));
    // A hand-off waiting in the shell, else this route's own arguments.
    final pending = shell?.analyticsRequest.value;
    _lastRequest = pending;
    final resolved = AnalyticsResolvedArgs.resolve(pending?.args ?? ModalRoute.of(context)?.settings.arguments);
    if (resolved.type != null) _applyPaidTo(resolved);
    _bootstrap(resolved.highlightTransactionId);
  }

  @override
  void dispose() {
    primaryShell?.analyticsRequest.removeListener(_onRequest);
    primaryShell?.periodLength.removeListener(_onSharedLength);
    _lifecycle.dispose();
    _highlightTimer?.cancel();
    _toastTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // §ANALYTICS.SHELL.HANDOFF — F5: living in the shell (hand-offs, recipient view).

  @override
  int get primaryTabIndex => PrimaryShellController.analyticsIndex;

  /// Back on the Analytics tab: fresh data, same period / filters / scroll.
  @override
  void onPrimaryTabShown() {
    if (!_handoffBusy) _load();
    // Back after the tour paused (system Back, another tab): pick it up.
    if (_tourOffered && primaryShell?.index.value == primaryTabIndex) _offerTour();
  }

  /// A hand-off from Home or Paid to into this live Analytics.
  Future<void> _onRequest() async {
    final req = primaryShell?.analyticsRequest.value;
    if (req == null || identical(req, _lastRequest) || !mounted) return;
    _lastRequest = req;
    final r = AnalyticsResolvedArgs.resolve(req.args);
    _handoffBusy = true;
    try {
      if (r.type != null) {
        setState(() {
          if (r.partyKey == null) _restoreBeforeParty();
          _applyPaidTo(r);
        });
        _pendingScroll = 0;
        await _load();
      } else {
        // Home's row: retarget to that transaction's Day (not a Home change).
        setState(() {
          _partyType = null;
          _partyKey = null;
          _partyName = null;
          _beforeParty = null;
          _typeFilter = null;
          _classFilter = null;
          _openRowId = null;
        });
        await _bootstrap(r.highlightTransactionId);
      }
    } finally {
      _handoffBusy = false;
    }
  }

  /// F6: Home changed its length; Analytics follows (filters cleared). In the
  /// recipient view it updates the state the close button returns to.
  void _onSharedLength() {
    final change = primaryShell?.periodLength.value;
    if (change == null || change.fromAnalytics || !mounted) return;
    final next = analyticsPeriodForHome(change.length, dateOnly(_now()));
    final saved = _beforeParty;
    if (_isParty && saved != null) {
      _beforeParty = AnalyticsBeforeParty(
        period: next,
        typeFilter: null,
        classFilter: null,
        whereTab: saved.whereTab,
        showAllClasses: saved.showAllClasses,
        scroll: 0,
      );
      return;
    }
    _setPeriod(next, broadcast: false);
  }

  /// A Paid to hand-off (T22, call in setState or before the first load):
  ///  - a recipient: the party view on Paid to's period (all time if none)
  ///    with its active category as the filter (the party already fixes the
  ///    type, so no type filter);
  ///  - an unnamed row / type shortcut (F8, now period-scoped): that period
  ///    with BOTH the type and, when given, the classification filter on
  ///    (T26 "yes allow type and category" — the old one-filter rule no
  ///    longer applies). Set directly, never broadcast: Home is untouched
  ///    (F6).
  void _applyPaidTo(AnalyticsResolvedArgs r) {
    final period = r.period ?? AnalyticsPeriod.allTime(dateOnly(_now()));
    if (r.partyKey != null) {
      _enterParty(r.type!, r.partyKey!, r.partyName);
      _period = period;
      _classFilter = r.classification;
      return;
    }
    _period = period;
    _typeFilter = r.type;
    _classFilter = r.classification;
    _openRowId = null;
  }

  /// Enters the recipient view, remembering the state the close button
  /// returns to.
  void _enterParty(String type, String key, [String? name]) {
    _beforeParty ??= AnalyticsBeforeParty(
      period: _period,
      typeFilter: _typeFilter,
      classFilter: _classFilter,
      whereTab: _whereTab,
      showAllClasses: _showAllClasses,
      scroll: _scroll.hasClients ? _scroll.offset : 0,
    );
    _partyType = type;
    _partyKey = key;
    _partyName = name;
    _typeFilter = null;
    _classFilter = null;
    _showAllClasses = false;
    _openRowId = null;
  }

  /// Leaves the recipient view for the state it had before (call in setState).
  void _restoreBeforeParty() {
    if (!_isParty) return;
    final saved = _beforeParty;
    _beforeParty = null;
    _partyType = null;
    _partyKey = null;
    _partyName = null;
    _period = saved?.period ?? AnalyticsPeriod.lastSevenDays(_now());
    _typeFilter = saved?.typeFilter;
    _classFilter = saved?.classFilter;
    _whereTab = saved?.whereTab ?? false;
    _showAllClasses = saved?.showAllClasses ?? false;
    _openRowId = null;
    _pendingScroll = saved?.scroll ?? 0;
  }

  /// Home's row hand-off: open on the Day of that transaction, with the row
  /// highlighted. A missing / deleted row or a failed lookup keeps the
  /// nav-bar default (the last 7 days) with no highlight.
  Future<void> _bootstrap(int? highlightId) async {
    if (highlightId != null) {
      DateTime? occurredAt;
      try {
        occurredAt = await AnalyticsDao.occurredAtOf(await _db(), id: highlightId);
      } catch (e) {
        debugPrint('Analytics: could not resolve transaction $highlightId for the Home hand-off: $e');
      }
      if (!mounted) return;
      if (occurredAt != null) {
        _period = AnalyticsPeriod.day(occurredAt);
        _pendingHighlightId = highlightId;
      }
    }
    await _load();
  }

  // §ANALYTICS.SHELL.LOAD — one fetch, one AnalyticsView snapshot.
  Future<void> _load() async {
    final seq = ++_loadSeq;
    final db = await _db();
    final now = _now();
    final today = dateOnly(now);
    final firstAt = await AnalyticsDao.firstOccurredAt(db);
    final first = firstAt == null ? null : dateOnly(firstAt);
    final party = _isParty;
    // T22: the recipient view keeps its own period (Paid to's, then stepped
    // like any other); only the vs-prior comparison is left out.
    final period = _period;

    final range = period.range(today: today, first: first);
    final prior = party ? null : period.priorRange(today: today, first: first);
    final chart = period.chart(now: now, first: first);

    // One fetch covers the period, its prior period and every chart bar.
    var (startMs, endMs) = range.bounds;
    if (prior != null) {
      startMs = math.min(startMs, prior.bounds.$1);
      endMs = math.max(endMs, prior.bounds.$2);
    }
    for (final b in chart.buckets) {
      startMs = math.min(startMs, b.startMs);
      endMs = math.max(endMs, b.endMs);
    }
    final rows = await AnalyticsDao.itemizedTransactions(
      db,
      startMs: startMs,
      endMs: endMs,
      types: AnalyticsDao.allTypes,
      partyType: _partyType,
      partyKey: _partyKey,
    );
    if (!mounted || seq != _loadSeq) return;

    final (rs, re) = range.bounds;
    final inc = [
      for (final r in rows)
        if (r.occurredAt.millisecondsSinceEpoch >= rs && r.occurredAt.millisecondsSinceEpoch <= re) r,
    ];
    int? priorCents;
    if (prior != null) {
      final (ps, pe) = prior.bounds;
      priorCents = rows
          .where((r) => r.occurredAt.millisecondsSinceEpoch >= ps && r.occurredAt.millisecondsSinceEpoch <= pe)
          .fold<int>(0, (s, r) => s + r.amountCents);
    }
    final bucketCents = [
      for (final b in chart.buckets)
        [
          for (final (code, _) in analyticsTypeOrder)
            rows
                .where((r) => r.sourceType == code && b.contains(r.occurredAt.millisecondsSinceEpoch))
                .fold<int>(0, (s, r) => s + r.amountCents),
        ],
    ];

    final scrollTo = _pendingScroll;
    _pendingScroll = null;
    setState(() {
      _view = AnalyticsView(
        period: period,
        party: party,
        partyType: party ? _partyType : null,
        now: now,
        first: first,
        range: range,
        inc: inc,
        priorCents: priorCents,
        chart: chart,
        bucketCents: bucketCents,
        partyName: party ? (_partyName ?? (rows.isEmpty ? null : rows.first.displayName)) : null,
      );
    });
    if (scrollTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(scrollTo.clamp(0.0, _scroll.position.maxScrollExtent));
      });
    }
    _maybeHighlight();
    if (!_tourOffered) {
      _tourOffered = true;
      _offerTour();
    }
  }

  /// Shows the tour (or its unfinished rest) once the frame has painted.
  void _offerTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: analyticsTourId, steps: _tourSteps());
    });
  }

  List<CoachStep> _tourSteps() {
    final rows = _view?.inc ?? const [];
    return analyticsTourSteps(
      granKey: _granKey,
      chartKey: _chartTourKey,
      breakdownKey: _breakdownTourKey,
      firstRowKey: rows.isEmpty ? null : _rowKeys.putIfAbsent(rows.first.id, GlobalKey.new),
    );
  }

  /// The header "?" replays the tour.
  void _replayTour() => CoachTour.start(context, pageId: analyticsTourId, steps: _tourSteps());

  void _maybeHighlight() {
    final id = _pendingHighlightId;
    if (id == null) return;
    // After the pending rebuild has laid the rows out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingHighlightId = null;
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx == null) return; // not in the current (filtered) list
      // About a third of the way down the screen (the mock's `clientHeight / 3`).
      Scrollable.ensureVisible(ctx, alignment: 1 / 3, duration: const Duration(milliseconds: 300));
      setState(() => _highlightedId = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(analyticsHighlightDuration, () {
        if (mounted) setState(() => _highlightedId = null);
      });
    });
  }

  // §ANALYTICS.SHELL.PERIOD — period changes (every one clears the filters).

  void _setPeriod(AnalyticsPeriod next, {bool broadcast = true}) {
    // F6: a LENGTH change to Day / Week / Month sets Home too (browsing within
    // a length, Year, All time and Custom never do).
    final home = homePeriodForAnalytics(next.granularity);
    if (broadcast && !_isParty && home != null && next.granularity != _period.granularity) {
      primaryShell?.periodLength.value = PeriodLengthChange(home, fromAnalytics: true);
    }
    setState(() {
      _period = next;
      _typeFilter = null;
      _classFilter = null;
      _openRowId = null;
    });
    _load();
  }

  void _step(int dir) {
    final v = _view;
    if (v == null) return;
    final ok = dir < 0 ? _period.canStepBack(today: v.today, first: v.first) : _period.canStepForward(today: v.today);
    if (!ok) return;
    _setPeriod(_period.step(dir, today: v.today));
  }

  /// Pull to refresh: re-query and return to the current period of the same
  /// length; filters cleared, scrolled to the top (the recipient view too,
  /// T22: it has a period now).
  Future<void> _backToNow() async {
    final today = dateOnly(_now());
    setState(() {
      _period = _period.backToNow(today: today);
      _typeFilter = null;
      _classFilter = null;
      _openRowId = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load();
  }

  /// The party card's close button: back to the state Analytics had before
  /// the recipient view (F5); the card stays until the re-query lands (F7).
  void _leaveParty() {
    setState(_restoreBeforeParty);
    _load();
  }

  // T26 "yes allow type and category": a type tile and a "Where it went" row
  // toggle only their own filter now; both can be active together (the list
  // filters on the AND of the two, see `analyticsTransactionSections`).
  void _toggleType(String code) => setState(() {
    _typeFilter = _typeFilter == code ? null : code;
  });

  void _toggleClass(String name) => setState(() {
    _classFilter = _classFilter == name ? null : name;
  });

  void _clearTypeFilter() => setState(() => _typeFilter = null);

  void _clearClassFilter() => setState(() => _classFilter = null);

  // §ANALYTICS.SHELL.PILL — the two-part period pill's menus and the Custom sheet.

  Future<T?> _showPop<T>(GlobalKey anchor, List<(String label, String note, bool selected, T value)> items) =>
      showPeriodMenu<T>(context, anchor: anchor, palette: AppPalette.of(context), items: items);

  Future<void> _openGranularityMenu() async {
    final v = _view;
    if (v == null) return;
    final picked = await _showPop<AnalyticsGranularity>(_granKey, [
      for (final (g, label) in analyticsGranularityMenu) (label, '', _period.granularity == g, g),
    ]);
    if (picked == null || !mounted) return;
    _setPeriod(_period.withGranularity(picked, today: v.today, first: v.first));
  }

  Future<void> _openValueMenu() async {
    final v = _view;
    if (v == null) return;
    final options = _period.options(today: v.today, first: v.first);
    if (options.isEmpty) {
      await _openCustomSheet(); // All time and Custom
      return;
    }
    final picked = await _showPop<AnalyticsPeriod>(_valueKey, [
      for (final o in options) (o.label, o.note, o.selected, o.period),
    ]);
    if (picked == null || !mounted) return;
    _setPeriod(picked);
  }

  Future<void> _openCustomSheet() async {
    final v = _view;
    if (v == null) return;
    final today = v.today;
    final end = v.range.end.isAfter(today) ? today : v.range.end;
    final start = v.range.start.isAfter(end) ? end : v.range.start;
    final picked = await showModalBottomSheet<AnalyticsPeriod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (ctx) => Theme(
        data: analyticsPickerTheme(AppPalette.of(context)),
        child: AnalyticsCustomDatesSheet(
          palette: AppPalette.of(context),
          from: start,
          to: end,
          today: today,
          firstDate: DateTime((v.first ?? today).year - 1, 1, 1),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _setPeriod(picked);
  }

  // §ANALYTICS.SHELL.EDIT — edit / delete (T13's data behaviour, T21's interaction).

  Future<void> _openEdit(AnalyticsTransactionRow tx) async {
    setState(() => _openRowId = null);
    final db = await _db();
    if (!mounted) return;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (ctx) => Theme(
        data: analyticsPickerTheme(AppPalette.of(context)),
        child: AnalyticsEditSheet(db: db, tx: tx, palette: AppPalette.of(context)),
      ),
    );
    if (!mounted || result == null) return;
    if (result is AnalyticsDeleteRequest) {
      await _delete(tx);
      return;
    }
    if (result is! AnalyticsEditResult) return;
    try {
      await TransactionDao.update(
        db,
        id: tx.id,
        amountCents: result.amountCents,
        transactionOccurredAt: result.transactionOccurredAt,
        classificationId: result.classificationId,
        counterpartyLabel: result.counterpartyLabel,
        counterpartyPhone: result.counterpartyPhone,
        paybillAccountNumber: result.paybillAccountNumber,
        transactionCostCents: result.transactionCostCents,
      );
    } on DatabaseException {
      // Plain wording only; the raw database text means nothing to the user.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the changes. If you fill in a name, fill in its phone or account number too.')),
      );
      return;
    }
    if (!mounted) return;
    _pendingHighlightId = tx.id;
    await _load();
  }

  /// No confirm step: soft-delete at once (it leaves every total), then a
  /// toast with Undo (PM-approved mock; replaces T13's confirm sheet).
  Future<void> _delete(AnalyticsTransactionRow tx) async {
    setState(() => _openRowId = null);
    final db = await _db();
    await TransactionDao.softDelete(db, id: tx.id);
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = '${tx.displayName} moved to Recently Deleted';
      _undoId = tx.id;
    });
    _toastTimer = Timer(analyticsToastDuration, _hideToast);
    await _load();
  }

  void _hideToast() {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _toastMessage = null;
      _undoId = null;
    });
  }

  Future<void> _undo() async {
    final id = _undoId;
    _hideToast();
    if (id == null) return;
    await TransactionDao.restore(await _db(), id: id);
    if (!mounted) return;
    _pendingHighlightId = id;
    await _load();
  }

  // §ANALYTICS.SHELL.BUILD

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final v = _view;
    return Stack(
      children: [
        PrimaryScaffold(
          title: 'Analytics',
          activeIndex: PrimaryShellController.analyticsIndex,
          followPhoneTheme: true,
          onHelp: v == null ? null : _replayTour,
          body: v == null
              ? Center(child: CircularProgressIndicator(color: palette.primary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The party strip is pinned above the scroll area.
                    if (v.party && v.partyType != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: AnalyticsPartyCard(
                          palette: palette,
                          type: v.partyType!,
                          name: v.partyName,
                          onClose: _leaveParty,
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        key: const Key('analyticsRefresh'),
                        color: palette.primary,
                        backgroundColor: palette.card,
                        onRefresh: _backToNow,
                        child: SingleChildScrollView(
                          key: const Key('analyticsScroll'),
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(14, v.party && v.partyType != null ? 8 : 6, 14, 40),
                          child: _body(v, palette),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (_toastMessage != null)
          Positioned(
            left: 12,
            right: 12,
            // 12px above the 66px nav (mock `.btoast` bottom:78px).
            bottom: 78 + MediaQuery.paddingOf(context).bottom,
            child: AnalyticsToast(palette: palette, message: _toastMessage!, onUndo: _undo),
          ),
      ],
    );
  }

  Widget _body(AnalyticsView v, AppPalette palette) {
    final words = v.period.words(today: v.today, first: v.first);
    final sections = <Widget>[
      // The mock's party slot still takes a flex gap; the party strip itself
      // is pinned above the scroll area (see build).
      const SizedBox.shrink(),
      AnalyticsHeroCard(
        palette: palette,
        view: v,
        words: words,
        granKey: _granKey,
        valueKey: _valueKey,
        onGranularity: _openGranularityMenu,
        onValue: _openValueMenu,
        onCustom: _openCustomSheet,
      ),
      KeyedSubtree(
        key: _chartTourKey,
        child: AnalyticsChartCard(
          palette: palette,
          view: v,
          typeFilterIndex: _typeFilter == null ? null : analyticsTypeOrder.indexWhere((t) => t.$1 == _typeFilter),
          canBack: _period.canStepBack(today: v.today, first: v.first),
          canForward: _period.canStepForward(today: v.today),
          onStep: _step,
          onBucket: (b) => _setPeriod(b.target!),
        ),
      ),
      AnalyticsBreakdownSwitch(
        palette: palette,
        whereTab: _whereTab,
        onChanged: (where) => setState(() => _whereTab = where),
      ),
      KeyedSubtree(
        key: _breakdownTourKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: _whereTab
              ? AnalyticsWherePanel(
                  palette: palette,
                  view: v,
                  typeFilter: _typeFilter,
                  classFilter: _classFilter,
                  showAll: _showAllClasses,
                  onToggleClass: _toggleClass,
                  onToggleShowAll: () => setState(() => _showAllClasses = !_showAllClasses),
                )
              : AnalyticsTypePanel(
                  palette: palette,
                  view: v,
                  typeFilter: _typeFilter,
                  classFilter: _classFilter,
                  onToggleType: _toggleType,
                ),
        ),
      ),
      ...analyticsTransactionSections(
        palette: palette,
        view: v,
        typeFilter: _typeFilter,
        classFilter: _classFilter,
        highlightedId: _highlightedId,
        openRowId: _openRowId,
        rowKeyFor: (id) => _rowKeys.putIfAbsent(id, GlobalKey.new),
        onOpened: (id, open) => setState(() => _openRowId = open ? id : null),
        onEdit: _openEdit,
        onDelete: _delete,
        onClearType: _clearTypeFilter,
        onClearClass: _clearClassFilter,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) SizedBox(height: i == 3 ? 9 : 11), // .bswitch margin-top:-2px
          sections[i],
        ],
      ],
    );
  }
}
