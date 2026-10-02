import 'dart:async';

import 'package:flutter/material.dart';

/// A + or - icon button for the Auto-backup steppers (B21b). A plain tap steps
/// by 1 (through the ordinary [IconButton], so TalkBack's double-tap works and
/// the tooltip stays the accessible label). Holding it down repeats: after
/// [holdDelay] it steps every [repeatEvery]; with [accelerate] it moves in
/// steps of 5 after about 2 s of repeating and 10 after about 4 s. It stops at
/// the bound, on release and when the pointer is cancelled. The step that is
/// applied never goes past [min] or [max].
class HoldStepButton extends StatefulWidget {
  const HoldStepButton({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.direction,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onStep,
    this.accelerate = false,
  });

  /// Key of the inner [IconButton] (tests read its `onPressed`).
  final Key? buttonKey;
  final IconData icon;
  final String tooltip;

  /// +1 for the plus button, -1 for the minus button.
  final int direction;

  /// The value shown now; the bound check reads it on every repeat.
  final int value;
  final int min;
  final int max;
  final bool enabled;

  /// Called with a signed amount (never crosses the bound).
  final ValueChanged<int> onStep;
  final bool accelerate;

  static const holdDelay = Duration(milliseconds: 400);
  static const repeatEvery = Duration(milliseconds: 80);

  /// Repeats at [repeatEvery] before the step grows to 5, and to 10.
  static const ticksToFive = 25; // about 2 s
  static const ticksToTen = 50; // about 4 s

  @override
  State<HoldStepButton> createState() => _HoldStepButtonState();
}

class _HoldStepButtonState extends State<HoldStepButton> {
  Timer? _delay;
  Timer? _repeat;
  int _ticks = 0;

  /// True once the hold has repeated; the release that follows must not also
  /// count as a tap.
  bool _held = false;

  bool get _canStep => widget.enabled && _room > 0;

  int get _room => widget.direction > 0 ? widget.max - widget.value : widget.value - widget.min;

  int get _stepSize {
    if (!widget.accelerate) return 1;
    if (_ticks >= HoldStepButton.ticksToTen) return 10;
    if (_ticks >= HoldStepButton.ticksToFive) return 5;
    return 1;
  }

  void _down(PointerDownEvent _) {
    _held = false;
    _stop();
    if (!_canStep) return;
    _delay = Timer(HoldStepButton.holdDelay, _startRepeating);
  }

  void _startRepeating() {
    _ticks = 0;
    _held = true;
    _tick();
    _repeat = Timer.periodic(HoldStepButton.repeatEvery, (_) {
      _ticks++;
      _tick();
    });
  }

  void _tick() {
    if (!_canStep) {
      _stop();
      return;
    }
    final step = _stepSize < _room ? _stepSize : _room;
    widget.onStep(widget.direction * step);
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  void _tap() {
    if (_held) return; // the hold already did the work
    widget.onStep(widget.direction);
  }

  @override
  void didUpdateWidget(HoldStepButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: IconButton(
        key: widget.buttonKey,
        tooltip: widget.tooltip,
        onPressed: _canStep ? _tap : null,
        icon: Icon(widget.icon),
      ),
    );
  }
}
