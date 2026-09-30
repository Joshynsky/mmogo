import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/prefs/app_prefs.dart';
import '../shell/routes.dart';
import '../theme/app_colors.dart';

/// Bundled image slots (T16). Each is a plain asset file under
/// `assets/onboarding/`, registered in pubspec.yaml, so the PM can replace a
/// placeholder with a real screenshot/crop by dropping in a file with the
/// same name — no code change. A missing or undecodable file falls back to
/// the plain tint area (see [_SlotImage]).
class OnboardingAssets {
  OnboardingAssets._();

  static const step1 = 'assets/onboarding/step1.png';
  static const step2Copy = 'assets/onboarding/step2_1.png';
  static const step2Paste = 'assets/onboarding/step2_2.png';
  static const step2Filled = 'assets/onboarding/step2_3.png';
  static const step3 = 'assets/onboarding/step3.png';
  static const step4 = 'assets/onboarding/step4.png';

  static const all = [step1, step2Copy, step2Paste, step2Filled, step3, step4];
}

class _Step {
  const _Step({required this.title, this.lines = const [], this.image, this.frames, this.isName = false});

  final String title;
  final List<String> lines;
  final String? image;
  final List<(String, String)>? frames; // (asset, caption)
  final bool isName;
}

/// Copy verbatim from the approved onboarding mock (v5).
const _steps = <_Step>[
  _Step(
    title: 'Track every shilling',
    lines: ['Your M-Pesa and cash spending, in one place.', 'It all stays on this phone. No account needed.'],
    image: OnboardingAssets.step1,
  ),
  _Step(
    title: 'Paste an M-Pesa SMS',
    lines: [
      'Copy the confirmation SMS, paste it into Add, and the details fill themselves in. '
          'You confirm before anything is saved.',
    ],
    frames: [
      (OnboardingAssets.step2Copy, 'Copy the M-Pesa SMS'),
      (OnboardingAssets.step2Paste, 'Tap Parse M-Pesa message and paste'),
      (OnboardingAssets.step2Filled, 'Details filled in, ready to confirm'),
    ],
  ),
  _Step(
    title: 'Cash counts too',
    lines: ['Paid in cash? Switch to the Cash tab and add it yourself.'],
    image: OnboardingAssets.step3,
  ),
  _Step(
    title: 'What should we call you?',
    lines: ['Optional. You can change it anytime in Profile.'],
    image: OnboardingAssets.step4,
    isName: true,
  ),
];

/// Number of onboarding steps.
int get onboardingStepCount => _steps.length;

/// T16 — the onboarding flow, built to the PM-approved clickable mock
/// (image-led, per the PM's design): a large rounded image area on top (56% of the screen), a
/// pill+dots progress indicator, a short text card, a wide "Next ›" pill
/// with a round deep-ocean Back "‹" from step 2 (chevron icons, mock v5),
/// and Skip top-right on its own row above the image. Reached only from the Welcome screen while the onboarding-complete
/// flag is unset. Skip and Get started both set the flag and reset the stack
/// to Home; Get started also saves a non-empty trimmed name through
/// [AppPrefs.writeUserDisplayName] (T17 BINDING — bumps Home's greeting
/// notifier). Skip saves nothing.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  int _step = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step < _steps.length - 1) setState(() => _step++);
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _finish({required bool saveName}) async {
    if (_finishing) return;
    _finishing = true;
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    if (saveName && name.isNotEmpty) {
      await AppPrefs.writeUserDisplayName(name);
    }
    // Proceeds to Home even if the flag write fails: never trap the user
    // here over a storage error (onboarding would just show again next
    // launch — see AppPrefs.readOnboardingComplete).
    await AppPrefs.writeOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Follows the chosen palette (T26 app-wide) and the phone's light/dark
    // setting; Ocean & Sun's own tokens are mock v3's own values.
    final palette = AppPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.overlayStyleWithNavBar(palette.background),
      child: PopScope(
        // System back walks back through the steps; on step 1 it leaves
        // the app as usual (Welcome was replaced, so there is nothing
        // under this route).
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: palette.background,
          body: AnimatedSwitcher(
            // Mock: `.screen{transition:opacity .28s ease}`, none under
            // reduced motion.
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, ?current],
            ),
            child: _StepPage(
              key: ValueKey(_step),
              index: _step,
              step: _steps[_step],
              nameController: _name,
              onNext: _next,
              onBack: _back,
              onSkip: () => _finish(saveName: false),
              onGetStarted: () => _finish(saveName: true),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    super.key,
    required this.index,
    required this.step,
    required this.nameController,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.onGetStarted,
  });

  final int index;
  final _Step step;
  final TextEditingController nameController;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 56% of the full screen height (mock `.img{flex:0 0 56%}`), taken from
    // the screen size rather than the body constraints so the image does
    // not shrink when the keyboard opens on the name step — the page
    // scrolls instead.
    // Skip sits on its own row above the image (on the page background), so no
    // image ever runs underneath it. The row plus the image together still
    // take 56% of the screen.
    final skipRowHeight = media.padding.top + 5 + 48 + 5;
    final imageHeight = media.size.height * 0.56 - skipRowHeight;
    return ColoredBox(
      color: AppPalette.of(context).background,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, media.padding.top + 5, 14, 5),
                    child: Align(alignment: Alignment.centerRight, child: _SkipButton(onPressed: onSkip)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(height: imageHeight, child: _ImageArea(step: step)),
                  ),
                  Expanded(
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _ProgressDots(index: index, count: _steps.length),
                            ),
                            const SizedBox(height: 14),
                            _TextCard(step: step, nameController: nameController),
                            const SizedBox(height: 14),
                            const Spacer(),
                            _NavRow(
                              showBack: index > 0,
                              isLast: step.isName,
                              onBack: onBack,
                              onNext: step.isName ? onGetStarted : onNext,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageArea extends StatelessWidget {
  const _ImageArea({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final frames = step.frames;
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: ColoredBox(
        key: const Key('onboarding-image-area'),
        color: palette.tint,
        child: frames == null
            ? _SlotImage(asset: step.image!)
            : Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: _ParseStrip(frames: frames),
              ),
      ),
    );
  }
}

/// One bundled image, `BoxFit.cover`, top-aligned. If the asset is missing or fails to
/// decode, [Image.errorBuilder] leaves an empty box, so the tint
/// background behind it shows through — never a crash or a broken-image
/// glyph. Decorative: the text card carries the meaning.
class _SlotImage extends StatelessWidget {
  const _SlotImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      key: ValueKey('onboarding-img:$asset'),
      fit: BoxFit.cover,
      // Anchored to the top: if the slot is shorter than the image, only the
      // bottom is trimmed, so the header of each screenshot stays visible.
      alignment: Alignment.topCenter,
      width: double.infinity,
      height: double.infinity,
      excludeFromSemantics: true,
      errorBuilder: (context, _, _) => ColoredBox(
        key: ValueKey('onboarding-img-fallback:$asset'),
        color: AppPalette.of(context).tint,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Step 2's 3-frame parse-flow strip: three phone-shaped (9:16) frames
/// joined by chevrons (mock v5 `›`), each with its numbered caption
/// underneath (the mock prints the number + caption inside the placeholder
/// frame; here they sit below it so a real screenshot is not covered).
class _ParseStrip extends StatelessWidget {
  const _ParseStrip({required this.frames});

  final List<(String, String)> frames;

  static const _arrowWidth = 22.0; // 6px gap + chevron + 6px gap (mock `.strip{gap:6px}`)

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = AppPalette.of(context);
        final width = constraints.maxWidth;
        final frameWidth = (width - _arrowWidth * (frames.length - 1)) / frames.length;
        final frameHeight = frameWidth * 16 / 9;
        final row = SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < frames.length; i++) ...[
                if (i > 0)
                  SizedBox(
                    width: _arrowWidth,
                    height: frameHeight,
                    child: Center(
                      // Decorative (mock `aria-hidden`). Icons ignore the
                      // text scale, like the old noScaling arrow.
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          key: const Key('onboarding-strip-chevron'),
                          size: _arrowWidth,
                          color: palette.tintInk,
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: frameWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: frameWidth,
                        height: frameHeight,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.frameLine, width: 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _SlotImage(asset: frames[i].$1),
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${i + 1}  ',
                              style: TextStyle(color: palette.tintInk, fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            TextSpan(text: frames[i].$2),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10.5, height: 1.3, color: palette.tintInk),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
        // Scale the whole strip down (never overflow) on short screens or
        // large text scales.
        return Center(child: FittedBox(fit: BoxFit.scaleDown, child: row));
      },
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final palette = AppPalette.of(context);
    return Semantics(
      key: const Key('onboarding-progress'),
      label: 'Step ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
              width: i == index ? 26 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? palette.brightPill : palette.dotIdle,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.step, required this.nameController});

  final _Step step;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lineStyle = TextStyle(fontSize: 13.5, height: 1.45, color: palette.softInk);
    final children = <Widget>[
      Text(
        step.title,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink),
      ),
      if (step.isName)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextField(
            key: const Key('onboarding-name-field'),
            controller: nameController,
            maxLength: AppPrefs.userDisplayNameMaxLength,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            style: TextStyle(fontSize: 15, color: palette.ink),
            cursorColor: palette.deep,
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: TextStyle(color: palette.mutedInk),
              filled: true,
              fillColor: palette.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.primary, width: 2),
              ),
            ),
          ),
        ),
      for (final line in step.lines) Text(line, textAlign: TextAlign.center, style: lineStyle),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.textCard, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.showBack, required this.isLast, required this.onBack, required this.onNext});

  final bool showBack;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  /// Horizontal paint offset that optically centres the Back chevron in
  /// its 48px circle (mock v5 `margin-left:-2px`).
  static const backChevronNudge = -1.5;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        if (showBack) ...[
          _FocusRing(
            shape: const CircleBorder(),
            child: Semantics(
              button: true,
              label: 'Back',
              excludeSemantics: true,
              onTap: onBack,
              child: FilledButton(
                key: const Key('onboarding-back'),
                onPressed: onBack,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.backBg,
                  foregroundColor: palette.backInk,
                  shape: const CircleBorder(),
                  fixedSize: const Size(48, 48),
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                // Mock v5 `‹` (SVG `M15 5l-7 7 7 7`, stroke 2.6, 26px,
                // margin-left -2px). Material's rounded chevron glyph fills
                // less of its box than the mock's path, so a 38px Icon
                // gives the same visible chevron (~10x18px). An Icon, not
                // a Text glyph, so there is no baseline offset: it is
                // centred vertically. Optical centring: a chevron's visual
                // weight sits on its open (right) side, so it is nudged
                // 1.5px left. Transform.translate is paint-only, so the
                // 48px circle and hit target are unchanged. The 'Back'
                // label above carries the meaning (excludeSemantics).
                child: Transform.translate(
                  offset: const Offset(_NavRow.backChevronNudge, 0),
                  child: Icon(Icons.chevron_left_rounded, size: 38, color: palette.backInk),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _FocusRing(
            shape: const StadiumBorder(),
            child: FilledButton(
              key: const Key('onboarding-next'),
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              child: isLast
                  ? const Text('Get started')
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Next'),
                        // Mock v5: a 20px SVG chevron 8px after the text.
                        // A 30px Material glyph gives the same visible
                        // chevron; it carries ~11px of its own side
                        // bearing, so a 3px gap matches the mock's visible
                        // text-to-chevron spacing.
                        const SizedBox(width: 3),
                        ExcludeSemantics(
                          child: Icon(Icons.chevron_right_rounded, size: 30, color: palette.onPrimary),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Visually the mock's small pill (7x14 padding); `padded` tap-target
    // size gives it a 48px-high hit area without changing the pill. Its
    // focus state is a deep-ocean outline on the pill itself (a [_FocusRing]
    // would wrap the invisible 48px hit box instead).
    final palette = AppPalette.of(context);
    return TextButton(
      key: const Key('onboarding-skip'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: palette.skipBg,
        foregroundColor: palette.skipInk,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        minimumSize: const Size(48, 30),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ).copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: palette.deep, width: 3, strokeAlign: BorderSide.strokeAlignOutside)
              : BorderSide.none,
        ),
      ),
      child: const Text('Skip'),
    );
  }
}

/// Visible keyboard-focus state (mock `button:focus-visible{outline:3px
/// solid var(--focus);outline-offset:2px}`): a 3px deep-ocean ring drawn 2px
/// outside the wrapped button whenever it has focus. It takes no layout
/// space and ignores pointer events.
class _FocusRing extends StatefulWidget {
  const _FocusRing({required this.shape, required this.child});

  final OutlinedBorder shape;
  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_focused)
            Positioned(
              left: -5,
              top: -5,
              right: -5,
              bottom: -5,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('onboarding-focus-ring'),
                  decoration: ShapeDecoration(
                    shape: widget.shape.copyWith(side: BorderSide(color: AppPalette.of(context).deep, width: 3)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
