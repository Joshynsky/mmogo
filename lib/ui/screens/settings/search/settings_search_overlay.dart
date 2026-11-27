import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/tap_target.dart';
import 'settings_search_entry.dart';
import 'settings_search_index.dart';
import 'settings_search_matcher.dart';

/// Test/debug switch: true draws the plain dim scrim instead of the blur.
bool kSettingsSearchPlainScrim = false;

/// Opens the search over the current page; the page behind stays visible (blurred). Pops itself, then calls [onPick].
Future<void> showSettingsSearch(BuildContext context, {required ValueChanged<SettingsSearchEntry> onPick, bool? autoRead}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, _) => SettingsSearchOverlay(
        entries: SettingsSearchIndex.entries(autoRead: autoRead),
        chips: SettingsSearchIndex.chips(autoRead: autoRead),
        onPick: (e) {
          Navigator.of(ctx).pop();
          onPick(e);
        },
        onClose: () => Navigator.of(ctx).pop(),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

/// §UI.SETTINGS.SEARCH — full-screen overlay: blurred page, field on top, chips (hidden while typing), result rows.
class SettingsSearchOverlay extends StatefulWidget {
  const SettingsSearchOverlay({super.key, required this.entries, required this.chips, required this.onPick, required this.onClose});

  final List<SettingsSearchEntry> entries;
  final List<String> chips;
  final ValueChanged<SettingsSearchEntry> onPick;
  final VoidCallback onClose;

  @override
  State<SettingsSearchOverlay> createState() => _SettingsSearchOverlayState();
}

class _SettingsSearchOverlayState extends State<SettingsSearchOverlay> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    _controller.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final plain = kSettingsSearchPlainScrim || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final typed = normalizeSearchText(_controller.text).isNotEmpty;
    final results = matchSettingsSearch(_controller.text, widget.entries);
    final scrim = ColoredBox(color: palette.background.withValues(alpha: plain ? 0.92 : 0.55));
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: kSettingsSearchBack,
              excludeSemantics: true,
              onTap: widget.onClose,
              child: GestureDetector(
                key: const Key('settingsSearchBarrier'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: plain ? scrim : BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), child: scrim),
              ),
            ),
          ),
          SafeArea(
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: kSettingsSearchLabel,
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(palette),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        if (typed) ...[for (final e in results) _row(palette, e)],
                        if (typed && results.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(kSettingsSearchNothing, key: const Key('settingsSearchNothing'), style: TextStyle(fontSize: 14, height: 1.4, color: palette.ink)),
                          ),
                        if (!typed || results.isEmpty) _chips(palette),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(AppPalette palette) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c, width: w));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: kMinTapTarget,
            height: kMinTapTarget,
            child: IconButton(
              key: const Key('settingsSearchBack'),
              tooltip: kSettingsSearchBack,
              icon: Icon(Icons.arrow_back, color: palette.ink),
              onPressed: widget.onClose,
            ),
          ),
          Expanded(
            child: TextField(
              key: const Key('settingsSearchField'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 16, color: palette.ink),
              decoration: InputDecoration(
                hintText: kSettingsSearchHint,
                filled: true,
                fillColor: palette.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: border(palette.line),
                enabledBorder: border(palette.line),
                focusedBorder: border(palette.primary, 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips(AppPalette palette) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in widget.chips)
          Semantics(
            button: true,
            label: c,
            excludeSemantics: true,
            onTap: () => _setQuery(c),
            child: InkWell(
              key: Key('settingsSearchChip:$c'),
              borderRadius: BorderRadius.circular(22),
              onTap: () => _setQuery(c),
              child: Container(
                // Sized by its text (no alignment/min width) so the chips flow across the row like the category
                // chips; the vertical padding keeps the tap target at 44 px.
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: palette.line, width: 1.5)),
                child: Text(c, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(AppPalette palette, SettingsSearchEntry e) {
    return Semantics(
      button: true,
      label: '${e.title}, ${e.sectionName}',
      excludeSemantics: true,
      onTap: () => widget.onPick(e),
      child: InkWell(
        key: Key('settingsSearchResult:${e.id}'),
        onTap: () => widget.onPick(e),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink)),
              Text(e.sectionName, style: TextStyle(fontSize: 12.5, color: palette.mutedInk)),
            ],
          ),
        ),
      ),
    );
  }
}
