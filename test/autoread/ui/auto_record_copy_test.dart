// Checks on the words of the Remembered page's second tab and the Settings row.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/airtime_kind_copy.dart';
import 'package:mmogo/autoread/ui/auto_record_copy.dart';

void main() {
  final texts = <String>[
    kAirKindMyselfLabel,
    kAirKindOtherLabel,
    kAutoRecordPageTitle,
    kAutoRecordRecipientsTab,
    kAutoRecordForgetAllLabel,
    kAutoRecordForgetAllNote,
    kAutoRecordChipAirtime,
    kAutoRecordChipsGroup,
    kAutoRecordMyselfSub,
    kAutoRecordOtherSub,
    autoRecordExplainTap(kAirKindMyselfLabel),
    autoRecordExplainTap(kAirKindOtherLabel),
    kAutoRecordExplainUndo,
    kAutoRecordExplainLater,
    kAutoRecordLaterTypes,
    autoRecordOnToast(kAirKindMyselfLabel),
    autoRecordOffToast(kAirKindOtherLabel),
    for (final (c, n) in kAutoRecordLaterChips) ...[c, n, autoRecordChipLaterSpoken(n)],
  ];

  test('fixed strings hold no digits and no dash characters', () {
    for (final s in texts) {
      expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
      expect(s.contains('—') || s.contains('–'), isFalse, reason: s);
    }
  });

  test('labels are the category names; explainer files under them', () {
    expect(kAirKindMyselfLabel, 'For myself');
    expect(kAirKindOtherLabel, 'For another number');
    expect(autoRecordExplainTap(kAirKindMyselfLabel),
        'You tap Parse on each message, then mmogo files it under For myself.');
    expect(autoRecordExplainTap(kAirKindOtherLabel), contains('under For another number.'));
    expect(kAutoRecordExplainLater, 'Filing without a tap comes in a later version.');
    expect(kAutoRecordExplainUndo, 'Each automatic record can be undone. You do not need to tap Categorize.');
  });

  test('ON toast says waiting parsed airtime is recorded at once', () {
    expect(autoRecordOnToast('X'),
        'X is on. You tap Parse each time. Airtime already parsed and waiting is recorded at once.');
    expect(autoRecordOffToast('X'), 'X is off. Nothing is recorded for you.');
  });

  test('number-bearing labels read as in the mock', () {
    expect(autoRecordTabLabel(2), 'Recorded automatically · 2');
  });

  test('every string const in the copy file carries a SIGNED or DRAFT tag', () {
    final lines = File('lib/autoread/ui/auto_record_copy.dart').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (RegExp(r'^(const|String|List)\b').hasMatch(l)) {
        final above = lines.sublist(0, i).reversed.take(1).join();
        expect(above.contains('SIGNED') || above.contains('DRAFT'), isTrue, reason: l);
      }
    }
  });
}
