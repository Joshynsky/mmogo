// S11b TS2 matrix, part 3: Home, Paid to, Recently deleted, Profile, Open
// failure (both outcomes and its retry states), start-up notice. Fakes only.
// Already covered elsewhere (not rebuilt here): see the matrix in
// _pipeline/v0.1.2/baseline/s11b-deviations.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:mmogo/ui/screens/open_failure_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:mmogo/ui/screens/profile_screen.dart';
import 'package:mmogo/ui/screens/recently_deleted_screen.dart';
import 'package:mmogo/ui/startup_notice.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';

import '../../support/a11y_matrix.dart';
import '../../support/fake_analytics_db.dart';
import '../../support/fake_home_db.dart';
import '../../support/fake_small_dbs.dart';

Finder _k(String key) => find.byKey(Key(key));

final _morning = DateTime(2026, 9, 24, 9, 30);

Widget _home(FakeHomeDb db) => HomeScreen(db: db, clock: () => _morning, startUpdates: () async {}, showWhatsNew: (_) async {});

const _homePeriodNote = 'NEW finding S11b: the Month/Week/Today text button on Home is 26-31 px high; a 44 px box grows the signed summary card, logged for the PM';

const _pillNote = 'NEW finding S11b: the pill is scaled down by a FittedBox beside the label, so its 44 px tap box scales with it; logged for the PM';

const _homeSeen = <String, Object>{'tour_seen_home': true};

List<A11yAction> _primary() => [
  A11yAction('Add button', _k('primaryFab'), floating: true),
  A11yAction('Notifications bell', find.byKey(const ValueKey('bell-button'))),
];

void main() {
  tearDownAll(printA11yLog);

  a11ySubject('Home, empty', prefs: _homeSeen, home: () => _home(FakeHomeDb(now: _morning)), actions: () => [
    ..._primary(),
    A11yAction('Period button', _k('homePeriodButton'), knownSmall: _homePeriodNote),
  ]);

  a11ySubject(
    'Home, with data',
    prefs: _homeSeen,
    home: () => _home(FakeHomeDb(
      now: _morning,
      thisTotal: 1254000,
      priorTotal: 900000,
      types: const {
        'SEND_MONEY': (700000, 9000),
        'BUY_GOODS': (300000, 0),
        'PAYBILL': (200000, 1500),
        'CASH': (54000, 0),
      },
      recentCount: 6,
    )),
    actions: () => [
      ..._primary(),
      A11yAction('Period button', _k('homePeriodButton'), knownSmall: _homePeriodNote),
    ],
  );

  final paidRows = [
    fakeTx(id: 21, at: DateTime(2026, 9, 5, 19), label: 'JOHN KAMAU', phone: '07000001', amountCents: 100000, costCents: 1300),
    fakeTx(id: 22, at: DateTime(2026, 9, 20, 9), label: 'ALICE', amountCents: 10000, classification: 'Rent', classificationId: 102),
    fakeTx(id: 23, at: DateTime(2026, 9, 8, 9), label: 'CAROL', amountCents: 5000),
  ];
  a11ySubject('Paid to, list', home: () => PaidToScreen(db: FakeAnalyticsDb(paidRows), clock: () => analyticsTestNow), actions: () => [
    ..._primary(),
    A11yAction('Search', _k('paidToSearch')),
    A11yAction('Filter button', _k('paidToFilterButton')),
    A11yAction('Granularity pill', viaTapTarget(_k('paidToGranularity')), knownSmall: _pillNote),
    A11yAction('Period pill', viaTapTarget(_k('paidToPeriodValue')), knownSmall: _pillNote),
  ]);

  a11ySubject(
    'Paid to, filter sheet',
    home: () => PaidToScreen(db: FakeAnalyticsDb(paidRows), clock: () => analyticsTestNow),
    open: (t) async {
      await t.tap(_k('paidToFilterButton'));
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Show', _k('paidToShow')),
      A11yAction('Reset', _k('paidToReset')),
    ],
  );

  a11ySubject('Recently deleted, empty', home: () => RecentlyDeletedScreen(db: FakeDeletedDb(0)), actions: () => [
    A11yAction('Back', find.byTooltip('Back')),
  ]);

  a11ySubject('Recently deleted, with rows', home: () => RecentlyDeletedScreen(db: FakeDeletedDb(3)), actions: () => [
    A11yAction('Back', find.byTooltip('Back')),
    A11yAction('Restore row 1', _k('deletedRowRestoreButton_1')),
    A11yAction('Restore row 3', _k('deletedRowRestoreButton_3')),
  ]);

  a11ySubject('Profile', home: () => ProfileScreen(db: FakeSummaryDb([DateTime(2026, 3, 4).millisecondsSinceEpoch, DateTime(2026, 9, 22).millisecondsSinceEpoch])), actions: () => [
    ..._primary(),
    A11yAction('Name field', _k('profile-name-field')),
  ]);

  for (final kind in OpenFailureKind.values) {
    for (final state in [(0, false, 'first screen'), (1, false, 'still not working'), (1, true, 'trying again')]) {
      a11ySubject(
        'Open failure, ${kind.name}, ${state.$3}',
        home: () => OpenFailureScreen(kind: kind, failedRetries: state.$1, trying: state.$2, onTryAgain: () {}),
        actions: () => [
          A11yAction('Try again', _k('openFailTryAgain')),
          A11yAction('Close app', _k('openFailClose')),
        ],
      );
    }
  }

  a11ySubject(
    'Start-up notice (snackbar)',
    home: () => const Scaffold(body: SizedBox()),
    before: () async => StartupNotice.resetForTest(),
    open: (t) async {
      expect(StartupNotice.maybeShow(outcome: ResetResumeOutcome.notFinished), isTrue);
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Notice text', _k('startupNotice')),
    ],
  );
}
