import '../../../domain/format/money.dart';

/// §PAIDTO.FORMAT — the money helper shared by the Paid to pieces.
/// "1,500" with no currency (the mock's `fee.toLocaleString('en-KE')`).
String paidToPlain(int cents) => kshTrim(cents).substring(4);
