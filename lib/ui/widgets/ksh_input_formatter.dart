import 'package:flutter/services.dart';

import '../../domain/format/ksh_amount.dart';

/// Lets an amount field hold only a valid shape (digits, one optional `.`,
/// at most two decimals): any edit or paste that would break it is ignored.
class KshInputFormatter extends TextInputFormatter {
  const KshInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      kshTypingShape.hasMatch(newValue.text) ? newValue : oldValue;
}
