// SP5: the three 0.1.2 source types are handled wherever the types are listed.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/counterparty/counterparty_key.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/type_icon.dart';

void main() {
  test('SmsSourceType has six values and each maps to a stored type', () {
    expect(SmsSourceType.values, hasLength(6));
    expect(
      {for (final v in SmsSourceType.values) v.dbValue},
      {'SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME'},
    );
  });

  test('sourceTypeOrder, AnalyticsDao.allTypes and the backup source types are the same seven', () {
    final order = [for (final (c, _) in sourceTypeOrder) c];
    expect(order, hasLength(7));
    expect(AnalyticsDao.allTypes, order.toSet());
    expect(kBackupSourceTypes.toSet(), order.toSet());
    // The four 0.1.1 types keep their places.
    expect(order.take(4).toList(), ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH']);
  });

  test('deriveCounterpartyKey does not throw for the new types and gives no key', () {
    for (final t in [SmsSourceType.pochi, SmsSourceType.agentWithdrawal, SmsSourceType.airtime]) {
      expect(
        deriveCounterpartyKey(
          sourceType: t,
          counterpartyLabel: 'Invented',
          counterpartyPhone: '0700000000',
          paybillAccountNumber: '1',
        ),
        '',
        reason: '$t',
      );
    }
    // The three 0.1.1 types are unchanged.
    expect(deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: ' a  b '), 'A B');
  });

  test('paidToTypes (the screen list) keeps Withdrawal, Airtime and Pochi out; the domain list has five (S7a)', () {
    expect(paidToTypes, ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS']);
    expect(paidToTypes, isNot(contains('AGENT_WITHDRAWAL')));
    expect(paidToTypes, isNot(contains('AIRTIME')));
    expect(paidToAllTypes, isNot(contains('AIRTIME')));
    // S7a: Withdrawal now has a captured identity (agent number or name); with neither it has none.
    expect(hasCapturedIdentity('AGENT_WITHDRAWAL', 'x', '07', 'y'), isTrue);
    expect(hasCapturedIdentity('AGENT_WITHDRAWAL', null, '07', 'y'), isFalse);
    expect(hasCapturedIdentity('AIRTIME', 'x', null, null), isFalse);
  });

  test('every type has a display name; the 0.1.1 icons and colours are unchanged', () {
    expect(sourceTypeName('AGENT_WITHDRAWAL'), 'Withdrawal');
    expect(sourceTypeName('AIRTIME'), 'Airtime');
    expect(sourceTypeName('POCHI_LA_BIASHARA'), 'Pochi');
    expect(sourceTypeName('CASH'), 'Cash');
    final p = AppPalette.light;
    expect(p.typeColor('SEND_MONEY'), p.typeSendMoney);
    expect(p.typeColor('PAYBILL'), p.typePaybill);
    expect(p.typeColor('BUY_GOODS'), p.typeBuyGoods);
    expect(p.typeColor('CASH'), p.typeCash);
    // The new types have their own signed colour (S4b) and never throw.
    expect(p.typeColor('POCHI_LA_BIASHARA'), p.typePochi);
    expect(p.typeColor('AGENT_WITHDRAWAL'), p.typeWithdrawal);
    expect(p.typeColor('AIRTIME'), p.typeAirtime);
    for (final c in ['POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME']) {
      expect(p.typeColor(c), isNot(p.mutedInk), reason: c);
      expect(sourceTypeIcon(c), isNot(sourceTypeIcon('CASH')), reason: c);
    }
  });
}
