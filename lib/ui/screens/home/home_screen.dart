import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/debug_seed.dart';
import '../../../data/db/home_dashboard_dao.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../domain/home/home_diff.dart';
import '../../../domain/home/home_greeting.dart';
import '../../../domain/home/home_period.dart';
import '../../../domain/home/recent_transaction.dart';
import '../../shell/primary_scaffold.dart';
import '../../shell/primary_shell.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/coach_tour.dart';
import 'home_consts.dart';
import 'recent_list.dart';
import 'summary_card.dart';

/// Home's coach-tour page id (the seen flag is `tour_seen_home`).
const homeTourId = 'home';

/// How many recent rows Home fetches; the screen shows as many of them as
/// fit whole ([HomeRecentSliver]).
const homeRecentFetchLimit = 30;

/// Primary destination 0 of 5 — T4's real Home, reworked by T20 to the
/// approved home-colours mock (v4):
///  - a time-of-day greeting with the display name in the (seamless) top bar;
///  - one merged card: the cycling period label, the period total, the ▲/▼
///    change vs the prior period, one bar per transaction type (bar length =
///    that type's share of the total), and the transaction cost row;
///  - as many whole recent transactions as fit, most recent first, each
///    handing off to Analytics.
/// Follows the phone's light/dark setting through [AppPalette.of].
///
/// Data comes from `home_dashboard_dao.dart` (unchanged by T20).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.db, this.clock});

  /// Test seam: the database to read. `null` = the app's real database
  /// (and, in debug builds only, the throwaway sample data is seeded).
  final Database? db;

  /// Test seam: "now" for the greeting and the period bounds.
  final DateTime Function()? clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with PrimaryTabRefresh<HomeScreen> {
  // §HOME.SHELL.STATE
  HomePeriod _period = HomePeriod.month;
  String? _name;
  bool _loading = true;
  int _loadSeq = 0;

  int _thisTotalCents = 0;
  int _priorTotalCents = 0;
  Map<String, SourceTypeTotal> _bySource = const {};
  List<RecentTransaction> _recent = const [];

  late final AppLifecycleListener _lifecycle;

  // Coach-tour anchors.
  final _periodTourKey = GlobalKey();
  final _cardTourKey = GlobalKey();
  final _firstRowTourKey = GlobalKey();
  final _fabTourKey = GlobalKey();
  bool _tourOffered = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Future<Database> _db() async => widget.db ?? await AppDatabase.instance.database;

  // §HOME.SHELL.LIFECYCLE
  @override
  void initState() {
    super.initState();
    // T21: back from the background, re-query (the period stays as it was).
    _lifecycle = AppLifecycleListener(onResume: _load);
    // T17 — Profile (pushed on top of this still-mounted Home) can edit the
    // display name; re-read it whenever it's written, so the greeting is
    // already correct when the user navigates back.
    AppPrefs.userDisplayNameRevision.addListener(_loadName);
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    final before = primaryShell;
    super.didChangeDependencies();
    final shell = primaryShell;
    if (shell == before) return;
    before?.periodLength.removeListener(_onSharedLength);
    shell?.periodLength.addListener(_onSharedLength);
    // F6: an Analytics length change made before Home was first built.
    final last = shell?.periodLength.value;
    if (last != null && last.fromAnalytics) _period = last.length;
  }

  @override
  void dispose() {
    primaryShell?.periodLength.removeListener(_onSharedLength);
    _lifecycle.dispose();
    AppPrefs.userDisplayNameRevision.removeListener(_loadName);
    super.dispose();
  }

  // F5: back on the Home tab, re-query; the period stays.
  @override
  int get primaryTabIndex => 0;

  @override
  void onPrimaryTabShown() {
    _load();
    // Back from a tour's "Take me there": pick the tour up where it paused.
    // (This also fires for data changes while another tab is showing.)
    if (_tourOffered && primaryShell?.index.value == primaryTabIndex) _offerTour();
  }

  /// F6: Analytics changed its length to Day / Week / Month.
  void _onSharedLength() {
    final change = primaryShell?.periodLength.value;
    if (change == null || !change.fromAnalytics || !mounted) return;
    if (change.length == _period) return;
    setState(() => _period = change.length);
    _load();
  }

  // §HOME.SHELL.LOAD
  Future<void> _loadName() async {
    final name = await AppPrefs.readUserDisplayName();
    if (mounted) setState(() => _name = name);
  }

  Future<void> _bootstrap() async {
    final db = await _db();
    // T13 — the app-launch purge sweep ("on app launch, before Home
    // renders"): runs before _load() populates any total, so a row that
    // just crossed its 1-hour grace window is never visible even for one
    // frame.
    await TransactionDao.purgeExpiredSoftDeletes(db);
    if (kDebugMode && widget.db == null) {
      await DebugSampleData.seedIfEmpty(db);
    }
    await _loadName();
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final db = await _db();
    final now = _now();
    final (start, end) = _period.bounds(now);
    final (priorStart, priorEnd) = _period.priorBounds(now);

    final results = await Future.wait([
      HomeDashboardDao.sumAmountCents(db, startMs: start, endMs: end),
      HomeDashboardDao.sumAmountCents(db, startMs: priorStart, endMs: priorEnd),
      HomeDashboardDao.sourceTypeTotals(db, startMs: start, endMs: end),
      HomeDashboardDao.recentTransactions(db, limit: homeRecentFetchLimit),
    ]);

    // A newer load (a quicker second period tap) wins.
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _thisTotalCents = results[0] as int;
      _priorTotalCents = results[1] as int;
      _bySource = results[2] as Map<String, SourceTypeTotal>;
      _recent = results[3] as List<RecentTransaction>;
      _loading = false;
    });
    // First tour: once, after the first data has painted.
    if (!_tourOffered) {
      _tourOffered = true;
      _offerTour();
    }
  }

  /// Shows the tour (or its unfinished rest) once the frame has painted.
  void _offerTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: homeTourId, steps: _tourSteps());
    });
  }

  /// The tour: with no transactions yet, just a pointer at + (nothing else
  /// has anything to show).
  List<CoachStep> _tourSteps() {
    final addStep = CoachStep(
      target: _fabTourKey,
      text: _recent.isEmpty
          ? 'Add your first transaction here: paste an M-Pesa message or enter cash.'
          : 'Add a transaction: paste an M-Pesa message or enter cash.',
      actionLabel: 'Take me there',
      onAction: () => Navigator.of(context).pushNamed(Routes.add),
    );
    if (_recent.isEmpty) return [addStep];
    return [
      CoachStep(target: _periodTourKey, text: 'Switch between Today, This week, This month and more.'),
      CoachStep(target: _cardTourKey, text: 'Your total, and how it compares with the last period.'),
      CoachStep(
        target: _firstRowTourKey,
        text: 'Tap a transaction to see it in Analytics.',
        actionLabel: 'Take me there',
        onAction: () {
          final shell = primaryShell;
          if (shell != null) {
            shell.select(1);
          } else {
            Navigator.of(context).pushNamed(Routes.analytics);
          }
        },
      ),
      addStep,
    ];
  }

  /// T21 pull to refresh: re-query and recompute everything time-derived —
  /// today's period bounds (in [_load]) and the time-of-day greeting (the
  /// rebuild), so a Home left open across 12:00 / 17:00 catches up.
  Future<void> _refresh() async {
    setState(() {});
    await _load();
  }

  // §HOME.SHELL.ACTIONS
  void _cyclePeriod() {
    // The card keeps showing the previous period's numbers until the new
    // ones arrive (no spinner flash on every tap).
    setState(() => _period = _period.next());
    // F6: Analytics follows Home's length (last change wins).
    primaryShell?.periodLength.value = PeriodLengthChange(_period, fromAnalytics: false);
    _load();
  }

  void _openTransaction(RecentTransaction tx) {
    // Hands the transaction id to Analytics, which opens on that
    // transaction's own day (T21) and scrolls it into view with a brief
    // highlight.
    // F5: inside the shell, retarget the live Analytics tab (no second
    // Analytics on the stack).
    final shell = primaryShell;
    if (shell != null) {
      shell.openAnalytics(tx.id);
      return;
    }
    Navigator.of(context).pushNamed(Routes.analytics, arguments: tx.id);
  }

  // §HOME.SHELL.BUILD
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PrimaryScaffold(
      title: homeGreeting(_now(), _name),
      activeIndex: 0,
      followPhoneTheme: true,
      fabTourKey: _fabTourKey,
      body: _loading ? Center(child: CircularProgressIndicator(color: palette.primary)) : _buildBody(palette),
    );
  }

  Widget _buildBody(AppPalette palette) {
    final diff = HomeDiff.compute(thisTotalCents: _thisTotalCents, priorTotalCents: _priorTotalCents);
    final totalCost = homeTypeOrder.fold<int>(0, (s, t) => s + (_bySource[t.$1]?.costCents ?? 0));

    return RefreshIndicator(
      key: const Key('homeRefresh'),
      color: palette.primary,
      backgroundColor: palette.card,
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const Key('homeScroll'),
        // Always scrollable so the pull works even when every row fits.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            sliver: SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _cardTourKey,
                child: HomeSummaryCard(
                periodTourKey: _periodTourKey,
                palette: palette,
                period: _period,
                totalCents: _thisTotalCents,
                diff: diff,
                typeTotals: {for (final (code, _) in homeTypeOrder) code: _bySource[code]?.totalCents ?? 0},
                costCents: totalCost,
                onPeriodTap: _cyclePeriod,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 6),
            sliver: SliverToBoxAdapter(
              child: Text(
                'RECENT TRANSACTIONS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: palette.mutedInk,
                ),
              ),
            ),
          ),
          HomeRecentSliver(
            palette: palette,
            recent: _recent,
            onTap: _openTransaction,
            firstRowTourKey: _firstRowTourKey,
          ),
        ],
      ),
    );
  }
}
