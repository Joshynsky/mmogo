// S11b TS2 matrix, part 2: Analytics (screen, party view, Categories sheet,
// Custom dates sheet, Edit sheet). See test/support/a11y_matrix.dart.
// Fakes only (FakeAnalyticsDb), invented rows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';

import '../../support/a11y_matrix.dart';
import '../../support/fake_analytics_db.dart';

Finder _k(String key) => find.byKey(Key(key));

Widget _screen() => AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow);

Future<void> _tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(_k(key));
  await t.pump();
  await t.tap(_k(key));
  await a11ySettle(t);
}

const _tabNote = 'NEW finding S11b: the By type / Where it went tabs are about 33 px high; the fix changes the signed tab height, logged for the PM';

const _pillNote = 'NEW finding S11b: the pill is scaled down by a FittedBox beside the label, and its 44 px tap box scales with it (37 px high at 1.3 on 360 px); the fix needs a layout decision, logged for the PM';

List<A11yAction> _screenActions() => [
  A11yAction('Granularity pill', viaTapTarget(_k('analyticsGranularity')), knownSmall: _pillNote),
  A11yAction('Period pill', viaTapTarget(_k('analyticsPeriodValue')), knownSmall: _pillNote),
  A11yAction('Calendar (custom dates)', _k('analyticsCalendar')),
  A11yAction('Previous period', _k('analyticsPrev')),
  A11yAction('Next period', _k('analyticsNext')),
  A11yAction('Tab By type', _k('analyticsTabType'), knownSmall: _tabNote),
  A11yAction('Tab Where it went', _k('analyticsTabWhere'), knownSmall: _tabNote),
  A11yAction('Type strip dot 1', _k('analyticsTypeDot0')),
  A11yAction('Type strip dot 2', _k('analyticsTypeDot1')),
  A11yAction('Add button', _k('primaryFab'), floating: true),
];

void main() {
  tearDownAll(printA11yLog);

  a11ySubject('Analytics, month with data (hero, chart, By type tiles)', home: _screen, actions: () => [
    ..._screenActions(),
    for (final c in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME'])
      A11yAction('Tile $c', _k('analyticsTypeTile-$c')),
  ]);

  a11ySubject(
    'Analytics, Where it went tab and Categories button',
    home: _screen,
    open: (t) => _tapKey(t, 'analyticsTabWhere'),
    actions: () => [
      A11yAction('Categories button', viaTapTarget(_k('analyticsCategoriesButton'))),
      A11yAction('Tab By type', _k('analyticsTabType'), knownSmall: _tabNote),
      A11yAction('Tab Where it went', _k('analyticsTabWhere'), knownSmall: _tabNote),
    ],
  );

  a11ySubject(
    'Analytics, Categories sheet',
    home: _screen,
    open: (t) async {
      await _tapKey(t, 'analyticsTabWhere');
      await _tapKey(t, 'analyticsCategoriesButton');
    },
    actions: () => [
      A11yAction('Close', _k('analyticsCatClose')),
      A11yAction('Clear', _k('analyticsCatClear')),
    ],
  );

  a11ySubject(
    'Analytics, Custom dates sheet',
    home: _screen,
    open: (t) => _tapKey(t, 'analyticsCalendar'),
    actions: () => [
      A11yAction('Show', _k('analyticsCustomShow')),
      A11yAction('Cancel', _k('analyticsCustomCancel')),
      A11yAction('From', _k('analyticsCustomFrom')),
      A11yAction('To', _k('analyticsCustomTo')),
    ],
  );

  a11ySubject(
    'Analytics, Edit sheet',
    home: _screen,
    open: (t) async {
      await _tapKey(t, 'analyticsRow-1');
      await _tapKey(t, 'analyticsRowEdit-1');
    },
    actions: () => [
      A11yAction('Save', _k('editSaveButton')),
      A11yAction('Cancel', _k('editCancelButton')),
      A11yAction('Delete', _k('editDeleteButton')),
    ],
  );

  a11ySubject(
    'Analytics, recipient (party) view',
    home: _screen,
    routeArgs: AnalyticsRouteArgs(
      type: 'SEND_MONEY',
      partyKey: 'no|0700000',
      partyName: 'JOHN KAMAU',
      period: AnalyticsPeriod.month(DateTime(2026, 9, 1), firstDay: 1),
    ),
    actions: () => [
      A11yAction('Close party strip', _k('analyticsPartyClose')),
      ..._screenActions(),
    ],
  );

  a11ySubject(
    'Analytics, a type filter on (filter chip and its clear control)',
    home: _screen,
    open: (t) => _tapKey(t, 'analyticsTypeTile-SEND_MONEY'),
    actions: () => [
      A11yAction('Type filter chip', viaTapTarget(_k('analyticsFilterChipType'))),
    ],
  );
}
