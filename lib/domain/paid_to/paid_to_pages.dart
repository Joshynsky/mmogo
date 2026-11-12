/// §DOMAIN.PAID_TO.PAGES — 0.2.0 S8: the paging maths of the Paybill ACCOUNTS block in Paid to's
/// recipient sheet (PM 03-11-2026: pages of 5 records, scrolled sideways, no Next / Previous, dots and
/// "Page n of N"; the same idea as Analytics' By type strip). Pure: no widgets.
library;

/// Records per page.
const paidToPageSize = 5;

/// A block of [total] records is paged only when it needs more than one page's worth of rows
/// (5 or fewer are just listed).
bool paidToNeedsPages(int total) => total > paidToPageSize;

/// The number of pages for [total] records: 0 for none, 25 -> 5, 24 -> 5, 26 -> 6.
int paidToPageCount(int total) => total <= 0 ? 0 : (total + paidToPageSize - 1) ~/ paidToPageSize;

/// The records on page [page] (0-based) of [items]; empty when [page] is out of range.
List<T> paidToPageItems<T>(List<T> items, int page) {
  if (page < 0) return const [];
  final start = page * paidToPageSize;
  if (start >= items.length) return const [];
  final end = start + paidToPageSize;
  return items.sublist(start, end > items.length ? items.length : end);
}

/// "Page 2 of 5" (1-based, as the person reads it). [page] is clamped into range.
String paidToPageLabel(int page, int pages) {
  if (pages <= 0) return '';
  final p = page < 0 ? 0 : (page >= pages ? pages - 1 : page);
  return 'Page ${p + 1} of $pages';
}

/// The page a scroll position falls on: the nearest page for [offset] pixels with pages [pageWidth] wide.
int paidToPageAt(double offset, double pageWidth, int pages) {
  if (pages <= 0 || pageWidth <= 0) return 0;
  final k = (offset / pageWidth).round();
  return k < 0 ? 0 : (k >= pages ? pages - 1 : k);
}
