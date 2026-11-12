/// §DOMAIN.AIRTIME.KIND — the two built-in Airtime categories (WBS row 17).
///
/// Airtime has TWO locked categories in its group: the kind of a saved airtime
/// entry is its category (no separate column). The parser decides the kind
/// (`for <digits>` = another number); the other number is never stored.
/// No screen, DAO or repository types these strings again.
library;

/// `seed_key` of the category for airtime bought for yourself (the 0.1.2
/// category, renamed [kAirtimeNameMyself] by schema version 5).
const String kAirtimeSeedMyself = 'AIRTIME:airtime';

/// `seed_key` of the category for airtime bought for another number (added by
/// schema version 5; a fresh install seeds it).
const String kAirtimeSeedOther = 'AIRTIME:for_another_number';

const String kAirtimeNameMyself = 'For myself';
const String kAirtimeNameOther = 'For another number';

/// The seed key of the category for a kind: [other] true = another number.
String airtimeSeedKey(bool other) => other ? kAirtimeSeedOther : kAirtimeSeedMyself;
