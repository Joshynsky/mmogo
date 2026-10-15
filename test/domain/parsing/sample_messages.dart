// Invented sample messages for the S8a parser tests (0.1.2). Every name,
// number, agent and receipt code here is made up; none is copied from a real
// message. The SHAPES follow the research notes.
library;

const String kSampleSendMoney =
    'QWE1R2T3Y4 Confirmed. Ksh500.00 sent to JANE  DOE 0712345678 on 8/10/26 '
    'at 9:15 AM. New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh7.00. '
    'Amount you can transact within the day is 499,000.00. Download My OneApp';

const String kSamplePaybill =
    'ZXC1V2B3N4 Confirmed. Ksh1,200.00 sent to SAMPLE POWER CO for account '
    '998877 on 8/10/26 at 6:30 PM. New M-PESA balance is Ksh900.00. '
    'Transaction cost, Ksh5.00. Amount you can transact within the day is 1.00.';

const String kSampleBuyGoods =
    'ASD1F2G3H4 Confirmed. Ksh350.00 paid to SAMPLE SHOP. on 8/10/26 at 1:05 PM.'
    'New M-PESA balance is Ksh900.00. Transaction cost, Ksh0.00.';

const String kSampleWithdrawal =
    'ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh2,000.00 from '
    '1234567 - SAMPLE AGENT NAME  New M-PESA balance is Ksh4,100.00. '
    'Transaction cost, Ksh29.00. Amount you can transact within the day is '
    '498,000.00. Download My OneApp';

const String kSampleAirtime =
    'PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 31/10/25 at '
    '2:01 PM.New M-PESA balance is Ksh77,777.77. Transaction cost, Ksh0.00.';

const String kSampleAirtimeOther =
    'TEJ4VG53X1 Confirmed. You bought Ksh104.00 of airtime on 21/5/24 at '
    '5:57 AM for 254712345678. New M-PESA balance is Ksh166,373.00.';

const String kSampleNameOnly =
    'POI1U2Y3T4 Confirmed. Ksh150.00 sent to Sample Person on 8/10/26 at '
    '4:45 PM. New M-PESA balance is Ksh800.00. Transaction cost, Ksh0.00.';

/// A Send Money message with the name, phone and fee swapped in.
String sendMoney({
  String name = 'JANE DOE',
  String phone = '0712345678',
  String fee = '7.00',
}) =>
    'QWE1R2T3Y4 Confirmed. Ksh500.00 sent to $name $phone on 8/10/26 at '
    '9:15 AM. New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh$fee.';

/// A name-only message with the name swapped in.
String nameOnly(String name) =>
    'POI1U2Y3T4 Confirmed. Ksh150.00 sent to $name on 8/10/26 at 4:45 PM. '
    'New M-PESA balance is Ksh800.00. Transaction cost, Ksh0.00.';
