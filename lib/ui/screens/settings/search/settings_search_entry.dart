import 'package:flutter/widgets.dart';

/// §UI.SETTINGS.SEARCH — one findable row of the Settings page (item 3, slice F).
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.title,
    required this.sectionName,
    this.keywords = const [],
    this.requiresAutoRead = false,
    this.standardOnly = false,
    this.requiresFuliza = false,
    this.targetKey,
  });

  /// Stable id, unique in the index; also the scroll-and-pulse id.
  final String id;
  final String title;

  /// Plain words people type ("dark", "pause", "csv").
  final List<String> keywords;
  final String sectionName;

  /// True when the row exists only in the Auto-read build.
  final bool requiresAutoRead;

  /// True when the row exists only in the standard build (Remembered recipients, Other version of mmogo).
  final bool standardOnly;

  /// True when the row is shown only while Fuliza is visible (Show Fuliza).
  final bool requiresFuliza;

  /// Optional key of the row's widget; integration may fill it. Otherwise [id] is used.
  final GlobalKey? targetKey;
}
