import 'package:flutter/material.dart';

import '../../data/prefs/app_prefs.dart';
import '../theme/app_colors.dart';

/// T19 — the shared contextual hint bubble (the contextual tip/hint
/// bubble, `.hint`), extracted from T9's Analytics-only
/// `_HintCard` so every hinted screen uses one implementation. Used on Home
/// and Add; Analytics' hint was removed by PM direct decision, 2026-09-24.
///
/// Binding rules (Phase 5 PM decisions) this host enforces structurally:
///  - **Occupies no layout space, shown or hidden.** The bubble is a
///    `Positioned` child of a `Stack` layered over [child] — never an
///    in-flow sibling — so [child]'s layout is identical either way.
///  - **Only "Got it" dismisses it, and only "Got it" marks it seen.** No
///    barrier, no tap-outside, no swipe-away, no timeout. [AppPrefs.
///    markHintSeen] is called from the Got it button's handler and nowhere
///    else.
///  - **Non-blocking.** There is no modal barrier; the bubble only absorbs
///    taps that land on the bubble itself — every control outside it keeps
///    working while it is shown.
///  - **Shown only while unseen** ([AppPrefs.readHintSeen], which fails
///    toward showing).
///
/// Positioning — two modes:
///  - **Anchored** ([anchorLink] non-null): the bubble's top edge sits
///    [gap] px below the bottom edge of whatever widget is wrapped in a
///    `CompositedTransformTarget(link: anchorLink)` — the real control the
///    hint's text instructs toward. The position is taken from the anchor's
///    actual painted location every frame (Flutter's `LayerLink` leader/
///    follower mechanism), not a one-off measurement, so it keeps tracking
///    the anchor when the content scrolls or the anchor's own height
///    changes (e.g. a row inside it appearing/disappearing) — the
///    exact class of bug this design once hit (a fixed offset floating
///    the hint over the control it told the user to tap). If the anchor is
///    not currently built at all (another tab, a loading spinner, a
///    confirm step), the bubble is simply not shown — never floated at a
///    guessed position — and the seen flag is NOT touched.
///  - **Fixed** ([anchorLink] null): floats at [fixedTop] from the top of
///    [child]'s area (Home: "a fixed offset just below the top bar").
///
/// The host clips its overlay to [child]'s own area, so an anchored bubble
/// can never paint over chrome outside that area (the app bar, Add's
/// M-Pesa/Cash switcher) even when the anchor scrolls up under it.
class HintOverlayHost extends StatefulWidget {
  const HintOverlayHost({
    super.key,
    required this.hintId,
    required this.message,
    required this.child,
    this.anchorLink,
    this.fixedTop = 16,
    this.gap = 8,
    this.horizontalInset = 16,
    this.enabled = true,
    this.gotItKey,
  });

  /// Per-hint id — persisted as `hint_seen_<hintId>` by [AppPrefs]. Must
  /// stay stable across releases (changing it re-shows the hint to users
  /// who already dismissed it).
  final String hintId;
  final String message;
  final Widget child;
  final LayerLink? anchorLink;
  final double fixedTop;
  final double gap;
  final double horizontalInset;

  /// Screen-level suppression (e.g. Add's Cash tab). While `false` the bubble is hidden but the seen flag is
  /// untouched, so it comes back once the suppression lifts.
  final bool enabled;

  /// Test/automation key for the Got it button. Defaults to
  /// `Key('hintGotIt_<hintId>')`.
  final Key? gotItKey;

  @override
  State<HintOverlayHost> createState() => _HintOverlayHostState();
}

class _HintOverlayHostState extends State<HintOverlayHost> {
  /// `null` until the pref read completes — nothing is shown before then.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _readSeen();
  }

  @override
  void didUpdateWidget(HintOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hintId != widget.hintId) {
      _seen = null;
      _readSeen();
    }
  }

  Future<void> _readSeen() async {
    final id = widget.hintId;
    final seen = await AppPrefs.readHintSeen(id);
    if (!mounted || id != widget.hintId) return;
    setState(() => _seen = seen);
  }

  /// The ONLY path that marks the hint seen — the explicit Got it tap.
  Future<void> _gotIt() async {
    setState(() => _seen = true);
    await AppPrefs.markHintSeen(widget.hintId);
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.enabled && _seen == false;
    final bubble = HintBubble(
      key: ValueKey('hintBubble_${widget.hintId}'),
      message: widget.message,
      onGotIt: _gotIt,
      gotItKey: widget.gotItKey ?? Key('hintGotIt_${widget.hintId}'),
    );
    final link = widget.anchorLink;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (show)
            Positioned(
              top: link == null ? widget.fixedTop : 0,
              left: widget.horizontalInset,
              right: widget.horizontalInset,
              child: link == null
                  ? bubble
                  : CompositedTransformFollower(
                      link: link,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: Offset(0, widget.gap),
                      child: bubble,
                    ),
            ),
        ],
      ),
    );
  }
}

/// The bubble itself — the `.hint` styling (light-blue
/// fill `#eaf6ff`, `#b8e0ff` 1px border, 10px radius, drop shadow, 12.5px
/// text) with a right-aligned "Got it" primary button as its only action.
class HintBubble extends StatelessWidget {
  const HintBubble({
    super.key,
    required this.message,
    required this.onGotIt,
    this.gotItKey,
  });

  final String message;
  final VoidCallback onGotIt;
  final Key? gotItKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6FF),
          border: Border.all(color: const Color(0xFFB8E0FF)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x29000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                message,
                style: const TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.35),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: gotItKey,
              onPressed: onGotIt,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Got it', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
