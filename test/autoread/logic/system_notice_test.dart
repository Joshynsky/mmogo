@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/held_describe.dart';
import 'package:mmogo/autoread/logic/message_details.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/unreadable_copy.dart';

import '../../support/waiting_fakes.dart' show heldIdFor;

void main() {
  const notice =
      'M-PESA is unable to process your request because a similar transaction is currently underway.';

  test('a system notice is recognised and labelled', () {
    expect(isSystemNotice(notice), isTrue);
    expect(lightRead(notice).notice, isTrue);
    expect(lightRead(notice).isEmpty, isFalse);
  });

  test('a confirmation or ordinary text is never a notice', () {
    expect(isSystemNotice('UKI8E2MHWO Confirmed. Ksh150.00 sent to MERAB'), isFalse);
    expect(isSystemNotice('UKI8E2MHWO Confirmed. similar transaction'), isFalse);
    expect(isSystemNotice('Some other text'), isFalse);
    expect(lightRead('Some other text').notice, isFalse);
  });

  test('details note says there is nothing to paste', () {
    final item = WaitingItem(id: heldIdFor(1), kind: WaitingKind.unreadable, heldAt: DateTime(2026, 11, 19, 10));
    final d = buildMessageDetails(item, DateTime(2026, 11, 19, 11), light: lightRead(notice));
    expect(d.note, kNoticeNote);
  });
}
