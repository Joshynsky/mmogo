/// §AUTOREAD.LAZY_CATEGORY_CHOICES - the Categorize sheet's own category list
/// ([RealCategoryChoices]: the active categories of one type's group, the same
/// ones Add shows) for a receiver type, opened when first asked. The Remembered
/// page's level sheet uses it so the Ask first category always belongs to the
/// person's own group. Auto-read build only.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../domain/parsing/parsed_sms_fields.dart';
import '../rules/rule_model.dart';
import '../ui/category_choices.dart';
import 'real_category_choices.dart';

/// The payment type a rule's receiver type is recorded under.
SmsSourceType sourceTypeOfReceiver(ReceiverType t) => switch (t) {
      ReceiverType.sendMoney => SmsSourceType.sendMoney,
      ReceiverType.payBill => SmsSourceType.payBill,
      ReceiverType.buyGoods => SmsSourceType.buyGoods,
      ReceiverType.pochi => SmsSourceType.pochi,
    };

class LazyCategoryChoices implements CategoryChoices {
  LazyCategoryChoices(this._db, this._type);
  final Future<Database> Function() _db;
  final SmsSourceType _type;

  @override
  Future<List<CategoryChoice>> categories() async => RealCategoryChoices(await _db(), _type).categories();

  @override
  Future<CategoryChoice> create(String name) async => throw StateError('New categories are made on Add.');
}
