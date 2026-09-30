/// Home's top-bar greeting (T20, PM direct decision, 2026-09-24): the time
/// of day plus the display name — "Good morning Shyn," / "Good afternoon
/// Shyn," / "Good evening Shyn," — or just "Good morning" etc. when no name
/// is set (no "Welcome back" any more).
///
/// Boundaries: before 12:00 is morning, before 17:00 is afternoon,
/// otherwise evening (local time of [now]). Pure and DB-free.
String homeGreeting(DateTime now, String? name) {
  final part = now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? part : '$part $trimmed,';
}
