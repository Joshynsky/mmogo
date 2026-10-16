// S11b AX1a (B3): visible app text writes "M-Pesa" with the non-breaking
// hyphen (U+2011) so it never wraps inside the name (defect F-8). Tests that
// look for visible text wrap their expected string in this helper instead of
// each retyping the escape. Semantics labels keep the ordinary hyphen (a
// screen reader reads them, nothing wraps), so those expectations stay as is.
const String kNonBreakingHyphen = '\u2011';

String mpesaText(String s) => s.replaceAll('M-Pesa', 'M${kNonBreakingHyphen}Pesa');
