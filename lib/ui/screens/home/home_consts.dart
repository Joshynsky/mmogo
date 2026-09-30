import '../../../domain/format/source_types.dart';

/// §HOME.CONST — Home's shared constants: the fixed type order and the tiny-screen
/// fallback row count.
/// The four transaction types in Home's fixed bar order (T20: the same
/// order every period, so a colour never moves) with their display names.
const homeTypeOrder = sourceTypeOrder;

/// When not even one whole recent row fits (a tiny screen or very large
/// text), Home becomes an ordinary scrolling page showing this many rows.
const homeRecentFallbackRows = 5;
