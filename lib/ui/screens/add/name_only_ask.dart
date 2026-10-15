import 'package:flutter/material.dart';

import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';

/// §ADD.NAME_ONLY_ASK — 0.1.2 S8c-2 (NO4). The bottom sheet "Is NAME on Pochi or
/// Send Money?", the line that stays on the form when it is closed without a
/// choice, and the "Remembered / Chosen" marker with its Change button. Strings
/// follow the signed mock `add.html` (U+2019 apostrophes). A name on screen here
/// is by design; it is never put in a snackbar, an error text or a log.

const String kNameOnlyChooseLine = 'Choose Pochi or Send Money.';
const String kNameOnlyAskBody =
    'This message has a name but no phone number, so we can’t tell. Choose one.';
const String kNameOnlyKeptNote =
    'The name is kept on this phone only. It is not in backups and not shared.';
const String kSendMoneyNameNote =
    'Send Money keeps a name only with a phone number. Add the phone below, or untick '
    '“Also record the receiver’s name & phone” and this saves as Unnamed.';

String nameOnlyAskTitle(String name) => 'Is $name on Pochi or Send Money?';
String nameOnlyTickLabel(
  String name, {
  required bool change,
  required bool on,
}) => change
    ? 'Remember this change (${on ? 'on' : 'off'})'
    : 'Remember this choice for $name';

/// Opens the ask. Returns the chosen type, or null when it was closed without a
/// choice (Back, the scrim, Esc, or a swipe down all give the same null).
/// [change] is true when a type already exists (the label then reads "Remember
/// this change"). The tick is shown only when [showTick] (the receiver-details
/// switch is on); [onTick] reports each tap so the screen keeps the state.
Future<SmsSourceType?> showNameOnlyAsk(
  BuildContext context, {
  required String name,
  required SmsSourceType? current,
  required bool showTick,
  required bool change,
  required bool tick,
  required ValueChanged<bool> onTick,
}) {
  return showModalBottomSheet<SmsSourceType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AskSheet(
      name: name,
      current: current,
      showTick: showTick,
      change: change,
      tick: tick,
      onTick: onTick,
    ),
  );
}

class _AskSheet extends StatefulWidget {
  const _AskSheet({
    required this.name,
    required this.current,
    required this.showTick,
    required this.change,
    required this.tick,
    required this.onTick,
  });

  final String name;
  final SmsSourceType? current;
  final bool showTick;
  final bool change;
  final bool tick;
  final ValueChanged<bool> onTick;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  late bool _tick = widget.tick;

  void _toggle() {
    setState(() => _tick = !_tick);
    widget.onTick(_tick); // the sheet stays open
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Esc, Back, the scrim and a swipe down all close a modal bottom sheet natively
    // (proved by the Esc test), with the same null result.
    return SafeArea(
      child: Container(
        key: const Key('addAskSheet'),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              nameOnlyAskTitle(widget.name),
              key: const Key('addAskTitle'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              kNameOnlyAskBody,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.mutedInk,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _choice(
                    palette,
                    SmsSourceType.pochi,
                    'Pochi',
                    const Key('addAskPochi'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _choice(
                    palette,
                    SmsSourceType.sendMoney,
                    'Send Money',
                    const Key('addAskSendMoney'),
                  ),
                ),
              ],
            ),
            if (widget.showTick) ...[
              const SizedBox(height: 8),
              InkWell(
                key: const Key('addAskTick'),
                onTap: _toggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTapTarget),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _tick,
                        activeColor: palette.primary,
                        checkColor: palette.onPrimary,
                        side: BorderSide(color: palette.mutedInk, width: 1.5),
                        onChanged: (_) => _toggle(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nameOnlyTickLabel(
                                widget.name,
                                change: widget.change,
                                on: _tick,
                              ),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              kNameOnlyKeptNote,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: palette.mutedInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choice(
    AppPalette palette,
    SmsSourceType type,
    String label,
    Key key,
  ) {
    final selected = widget.current == type;
    final style = selected
        ? FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.onPrimary,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: palette.primary,
            side: BorderSide(color: palette.primary, width: 1.5),
          );
    final child = Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 44,
        child: selected
            ? FilledButton(
                key: key,
                style: style,
                onPressed: () => Navigator.of(context).pop(type),
                child: child,
              )
            : OutlinedButton(
                key: key,
                style: style,
                onPressed: () => Navigator.of(context).pop(type),
                child: child,
              ),
      ),
    );
  }
}

/// What stays on the form when the ask was closed without a choice: the line and
/// a "Choose" button that reopens the ask.
class NameOnlyAwaitRow extends StatelessWidget {
  const NameOnlyAwaitRow({super.key, required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('addAskAwait'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kNameOnlyChooseLine,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
          ),
          TextButton(
            key: const Key('addAskChooseButton'),
            onPressed: onChoose,
            style: TextButton.styleFrom(
              foregroundColor: palette.primary,
              minimumSize: const Size(44, 44),
            ),
            child: const Text(
              'Choose',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Remembered · Pochi" / "Chosen · Pochi" with a Change button, and (Send Money)
/// the note that a name needs a phone.
class NameOnlyMarker extends StatelessWidget {
  const NameOnlyMarker({
    super.key,
    required this.remembered,
    required this.typeName,
    required this.sendMoney,
    required this.onChange,
  });

  final bool remembered;
  final String typeName;
  final bool sendMoney;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('addAskMarker'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${remembered ? 'Remembered' : 'Chosen'} · $typeName',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
              TextButton(
                key: const Key('addAskChangeButton'),
                onPressed: onChange,
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  minimumSize: const Size(44, 44),
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        if (sendMoney)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Text(
              kSendMoneyNameNote,
              key: const Key('addSendMoneyNameNote'),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: palette.mutedInk,
              ),
            ),
          ),
      ],
    );
  }
}
