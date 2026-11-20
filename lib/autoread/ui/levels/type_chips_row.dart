/// §AUTOREAD.LEVELS.TYPE_CHIPS: the type chips under the level filter, money out
/// first: Send Money, Paybill, Buy Goods, Pochi, Withdrawals (muted), Airtime.
/// Exactly one type is open at a time (there is no "All"); tapping the open chip
/// does nothing. The short code (SM, PB...) stays the tag on each row.
library;

import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart' show sourceTypeName;
import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'levels_copy.dart';

enum TypeChip {
  sendMoney(kChipSendMoney, kSpokenSendMoney, ReceiverType.sendMoney),
  payBill(kChipPayBill, kSpokenPayBill, ReceiverType.payBill),
  buyGoods(kChipBuyGoods, kSpokenBuyGoods, ReceiverType.buyGoods),
  pochi(kChipPochi, kSpokenPochi, ReceiverType.pochi),
  withdrawal(kChipWithdrawal, kSpokenWithdrawal, null),
  airtime('', '', null);

  final String _code;
  final String _spoken;
  final ReceiverType? receiver;
  const TypeChip(this._code, this._spoken, this.receiver);

  /// Short code, the tag on a row and part of the chip's key (the Airtime one uses the type name).
  String get code => this == TypeChip.airtime ? sourceTypeName('AIRTIME') : _code;
  /// Readable name: the chip text and its spoken name.
  String get spoken => this == TypeChip.airtime ? sourceTypeName('AIRTIME') : _spoken;

  /// Only withdrawal is muted in 0.2.1.
  bool get muted => this == TypeChip.withdrawal;

  Color color(AppPalette p) => switch (this) {
        TypeChip.airtime => p.typeAirtime,
        TypeChip.sendMoney => p.typeSendMoney,
        TypeChip.payBill => p.typePaybill,
        TypeChip.buyGoods => p.typeBuyGoods,
        TypeChip.withdrawal => p.typeWithdrawal,
        TypeChip.pochi => p.typePochi,
      };
}

/// The chip of a receiver type.
TypeChip chipOf(ReceiverType t) => switch (t) {
      ReceiverType.sendMoney => TypeChip.sendMoney,
      ReceiverType.payBill => TypeChip.payBill,
      ReceiverType.buyGoods => TypeChip.buyGoods,
      ReceiverType.pochi => TypeChip.pochi,
    };

class TypeChipsRow extends StatelessWidget {
  const TypeChipsRow({super.key, required this.selected, required this.onChanged});

  final TypeChip selected;
  final ValueChanged<TypeChip> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Semantics(
        container: true,
        label: kTypeChipsGroup,
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final c in TypeChip.values) _chip(p, c),
        ]),
      ),
    );
  }

  Widget _chip(AppPalette p, TypeChip c) {
    final on = selected == c;
    final col = c.color(p);
    if (c.muted) {
      return Semantics(
        container: true,
        enabled: false,
        label: chipComingLaterSpoken(c.spoken),
        excludeSemantics: true,
        child: Opacity(
          opacity: .5,
          child: Container(
            key: Key('typeChip${c.code}'),
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(999)),
            child: Center(widthFactor: 1, child: Text(c.spoken, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.softInk))),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      selected: on,
      label: c.spoken,
      excludeSemantics: true,
      onTap: () => onChanged(c),
      child: InkWell(
        key: Key('typeChip${c.code}'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(c),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? p.tint : Colors.transparent,
            border: Border.all(color: on ? col : p.line, width: 1.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(c.spoken, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? p.tintInk : p.ink)),
          ),
        ),
      ),
    );
  }
}
