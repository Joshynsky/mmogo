@Tags(['autoread'])
library;

// F2b: the auto-read WaitingRow, every kind.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/waiting_row.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/notif_colors.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';

import '../../support/waiting_fakes.dart';

final DateTime _now = DateTime(2026, 10, 18, 10, 0);

Widget host(Widget child, {String palette = 'ocean', String mode = 'light', double scale = 1.0}) {
  return AppPaletteScope(
    controller: AppPaletteController(palette, mode),
    child: MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child)),
      ),
    ),
  );
}

void size360(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(360, 800);
  addTearDown(t.view.reset);
}

int _n = 1;

/// A held item that has [left] before it runs out.
WaitingItem held(WaitingKind kind, {Duration left = const Duration(hours: 20)}) => WaitingItem(
      id: heldIdFor(_n++),
      kind: kind,
      heldAt: _now.subtract(kHeldWindow - left),
    );

ParsedSmsFields fields({String? name = 'Sample Shop', SmsSourceType type = SmsSourceType.sendMoney}) => ParsedSmsFields(
      code: 'SAMPLECODE9',
      sourceType: type,
      amountCents: 64000,
      transactionCostCents: 0,
      counterpartyLabel: name,
      counterpartyPhone: '0700123456',
      paybillAccountNumber: null,
      transactionOccurredAt: _now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    );

WaitingItem cat({bool flagged = false, String? name = 'Sample Shop', SmsSourceType type = SmsSourceType.sendMoney}) =>
    WaitingItem(
      id: heldIdFor(_n++),
      kind: WaitingKind.waitingCategory,
      heldAt: _now.subtract(const Duration(hours: 2)),
      parsed: fields(name: name, type: type),
      sameCodeDifferentDetails: flagged,
    );

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Iterable<String> _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '');

void main() {
  testWidgets('ready to parse: texts, diamond-dot icon, only Parse, callback', (t) async {
    var parsed = 0;
    await t.pumpWidget(host(WaitingRow(held(WaitingKind.readyToParse), _now, onParse: () => parsed++)));
    expect(find.text(kReadyRowTitle), findsOneWidget);
    expect(find.textContaining('expires in 20 h'), findsOneWidget);
    expect(t.widget<NotifShapeIcon>(find.byType(NotifShapeIcon)).shape, NotifShape.diamondDot);
    expect(find.byKey(const Key('waitingRowDimIcon')), findsNothing);
    expect(find.text(kActionParse), findsOneWidget);
    for (final w in [kActionRemove, kActionPaste, kActionCategorize, 'Dismiss']) {
      expect(find.text(w), findsNothing, reason: w);
    }
    await t.tap(find.text(kActionParse));
    expect(parsed, 1);
  });

  testWidgets('ready to parse: expires-in text at 20 h, under 1 h and exactly 1 h', (t) async {
    await t.pumpWidget(host(WaitingRow(held(WaitingKind.readyToParse, left: const Duration(hours: 20)), _now)));
    expect(find.textContaining(expiresInLine(hours: 20, underOneHour: false)), findsOneWidget);
    await t.pumpWidget(host(WaitingRow(held(WaitingKind.readyToParse, left: const Duration(minutes: 40)), _now)));
    expect(find.textContaining('expires in under 1 h'), findsOneWidget);
    await t.pumpWidget(host(WaitingRow(held(WaitingKind.readyToParse, left: const Duration(hours: 1)), _now)));
    expect(find.textContaining('expires in 1 h'), findsOneWidget);
    expect(find.textContaining('under 1 h'), findsNothing);
  });

  testWidgets('a ready row past the held window shows as gone', (t) async {
    await t.pumpWidget(host(WaitingRow(
      WaitingItem(id: heldIdFor(_n++), kind: WaitingKind.readyToParse, heldAt: _now.subtract(kHeldWindow)),
      _now,
    )));
    expect(find.text(kGoneLine), findsOneWidget);
    expect(find.text(kActionParse), findsNothing);
  });

  testWidgets('no raw message text, code or phone number in the tree (ready, unreadable, gone, waiting)', (t) async {
    final items = [
      held(WaitingKind.readyToParse),
      held(WaitingKind.unreadable),
      held(WaitingKind.gone),
      cat(),
    ];
    await t.pumpWidget(host(Column(children: [for (final i in items) WaitingRow(i, _now)])));
    for (final s in _allText(t)) {
      expect(s, isNot(contains('SAMPLECODE9')));
      expect(s, isNot(contains('0700123456')));
      expect(s.toLowerCase(), isNot(contains('confirmed')));
    }
  });

  testWidgets('waiting category: title from the parsed fields, Categorize only, no flag', (t) async {
    var n = 0;
    await t.pumpWidget(host(WaitingRow(cat(), _now, onCategorize: () => n++)));
    expect(find.text('Sent Ksh 640 to Sample Shop'), findsOneWidget);
    expect(find.text(kActionCategorize), findsOneWidget);
    for (final w in [kActionRemove, kActionPaste, kActionParse, 'Dismiss']) {
      expect(find.text(w), findsNothing, reason: w);
    }
    expect(find.byKey(const Key('waitingRowFlag')), findsNothing);
    expect(find.text(kFlaggedLine), findsNothing);
    expect(t.widget<Container>(find.byKey(const Key('waitingRowPillIcon'))), isNotNull);
    await t.tap(find.text(kActionCategorize));
    expect(n, 1);
  });

  testWidgets('waiting category: the flagged line only when flagged, Categorize kept, still no Remove', (t) async {
    await t.pumpWidget(host(WaitingRow(cat(flagged: true), _now)));
    expect(find.text(kFlaggedLine), findsOneWidget);
    expect(find.text(kActionCategorize), findsOneWidget);
    expect(find.text(kActionRemove), findsNothing);
  });

  test('waitingTitle covers every source type and a missing name', () {
    expect(waitingTitle(fields(type: SmsSourceType.payBill)), 'Paid Ksh 640 to Sample Shop');
    expect(waitingTitle(fields(type: SmsSourceType.buyGoods)), 'Paid Ksh 640 to Sample Shop');
    expect(waitingTitle(fields(type: SmsSourceType.agentWithdrawal)), 'Withdrew Ksh 640 from Sample Shop');
    expect(waitingTitle(fields(type: SmsSourceType.airtime)), 'Bought airtime Ksh 640');
    expect(waitingTitle(fields(name: null)), 'Sent Ksh 640');
    expect(waitingTitle(fields(name: '  ')), 'Sent Ksh 640');
  });

  testWidgets('unreadable: copy, dimmed icon, Paste and Remove, callbacks', (t) async {
    final calls = <String>[];
    await t.pumpWidget(host(WaitingRow(
      held(WaitingKind.unreadable),
      _now,
      onPaste: () => calls.add('paste'),
      onRemove: () => calls.add('remove'),
      onParse: () => calls.add('parse'),
    )));
    expect(find.text(kCouldNotRead), findsOneWidget);
    expect(find.byKey(const Key('waitingRowDimIcon')), findsOneWidget);
    expect(find.text(kActionParse), findsNothing);
    expect(find.text(kActionPaste), findsOneWidget);
    expect(find.text(kActionRemove), findsOneWidget);
    await t.tap(find.text(kActionPaste));
    await t.tap(find.text(kActionRemove));
    expect(calls, ['paste', 'remove']);
  });

  testWidgets('gone: copy with the recovery wording, Expired footer, Paste and Remove', (t) async {
    final calls = <String>[];
    await t.pumpWidget(host(WaitingRow(
      held(WaitingKind.gone),
      _now,
      onPaste: () => calls.add('paste'),
      onRemove: () => calls.add('remove'),
    )));
    expect(find.text(kGoneLine), findsOneWidget);
    expect(find.text(kGoneRecovery), findsOneWidget);
    expect(find.text(kGoneFooter), findsOneWidget);
    expect(find.byKey(const Key('waitingRowDimIcon')), findsOneWidget);
    await t.tap(find.text(kActionPaste));
    await t.tap(find.text(kActionRemove));
    expect(calls, ['paste', 'remove']);
  });

  testWidgets('spoken labels per kind', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host(Column(children: [
      WaitingRow(held(WaitingKind.readyToParse), _now),
      WaitingRow(cat(flagged: true), _now),
      WaitingRow(held(WaitingKind.unreadable), _now),
      WaitingRow(held(WaitingKind.gone), _now),
    ])));
    expect(find.bySemanticsLabel(RegExp(r'^Ready to parse\. M-Pesa message ready\. Received 4 hours ago · expires in 20 hours\.$')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Waiting for a category\. Sent Ksh 640 to Sample Shop\. .*same code, different details')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ready to parse, could not be read\. Could not read this one')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Message gone\. This message is no longer available')), findsOneWidget);
    expect(find.bySemanticsLabel('Parse the M-Pesa message received 4 hours ago'), findsOneWidget);
    expect(find.bySemanticsLabel('Categorize: Sent Ksh 640 to Sample Shop'), findsOneWidget);
    h.dispose();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('360 px, text x$scale, long names: no overflow, 44 px targets', (t) async {
      size360(t);
      final long = 'Mwangi Wanjiku Kiprotich Odhiambo Achieng Wambui Njoroge Cherono ' * 2;
      await t.pumpWidget(host(
        Column(children: [
          WaitingRow(held(WaitingKind.readyToParse), _now, onParse: () {}),
          WaitingRow(cat(flagged: true, name: long), _now, onCategorize: () {}),
          WaitingRow(held(WaitingKind.unreadable), _now, onPaste: () {}, onRemove: () {}),
          WaitingRow(held(WaitingKind.gone), _now, onPaste: () {}, onRemove: () {}),
        ]),
        scale: scale,
      ));
      expect(t.takeException(), isNull);
      final wells = find.byType(InkWell);
      expect(wells, findsNWidgets(1 + 1 + 2 + 2));
      for (final e in wells.evaluate()) {
        final s = t.getSize(find.byElementPredicate((x) => x == e));
        expect(s.width, greaterThanOrEqualTo(44));
        expect(s.height, greaterThanOrEqualTo(44));
      }
    });
  }

  group('contrast of waiting row text on the row surface', () {
    final sets = <String, AppPalette>{
      'ocean light': AppPalette.light,
      'ocean dark': AppPalette.dark,
      'leaf light': AppPalette.leafLight,
      'leaf dark': AppPalette.leafDark,
      'indigo light': AppPalette.indigoLight,
      'indigo dark': AppPalette.indigoDark,
    };
    for (final e in sets.entries) {
      final p = e.value;
      test('${e.key}: title, subtitle and age line on surface; flag text on its box', () {
        expect(_ratio(p.ink, p.surface), greaterThanOrEqualTo(4.5));
        expect(_ratio(p.mutedInk, p.surface), greaterThanOrEqualTo(4.5));
        expect(_ratio(p.ink, p.textCard), greaterThanOrEqualTo(4.5));
      });
      test('${e.key}: diamond and pill icons on surface >= 3:1; glyph ink on fill >= 3:1', () {
        for (final s in [NotifShape.diamondDot, NotifShape.pill]) {
          expect(_ratio(notifShapeColor(p, s), p.surface), greaterThanOrEqualTo(3.0), reason: '$s');
          expect(_ratio(notifShapeInk(p, s), notifShapeColor(p, s)), greaterThanOrEqualTo(3.0), reason: '$s ink');
        }
      });
    }
  });
}
