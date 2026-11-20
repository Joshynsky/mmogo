/// §AUTOREAD.LEVELS.AIRTIME_SWITCHES: the two airtime switches (For myself, For
/// another number) on the second tab. Moved unchanged from the old tab: same
/// keys, same signed words, same controller. Shown under the type chips when the
/// Airtime chip is chosen. The rules text is in the page's "?" sheet, not here.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../logic/airtime_auto.dart';
import '../airtime_kind_copy.dart' show kAirKindMyselfLabel, kAirKindOtherLabel;
import '../auto_record_copy.dart' show autoRecordOffToast, autoRecordOnToast, kAutoRecordMyselfSub, kAutoRecordOtherSub;

class AirtimeSwitches extends StatelessWidget {
  const AirtimeSwitches({super.key, required this.controller});
  final AirtimeAutoController controller;

  void _toast(BuildContext context, String text) => PillToast.show(text);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _AirRow(
          rowKey: 'autoRecordMyself',
          label: kAirKindMyselfLabel,
          sub: kAutoRecordMyselfSub,
          value: controller.on,
          onChanged: (v) {
            controller.onSwitch(v);
            _toast(context, v ? autoRecordOnToast(kAirKindMyselfLabel) : autoRecordOffToast(kAirKindMyselfLabel));
          },
        ),
        _AirRow(
          rowKey: 'autoRecordOther',
          label: kAirKindOtherLabel,
          sub: kAutoRecordOtherSub,
          value: controller.onOther,
          onChanged: (v) {
            final f = controller.onSwitchOther;
            if (f == null) return;
            f(v);
            _toast(context, v ? autoRecordOnToast(kAirKindOtherLabel) : autoRecordOffToast(kAirKindOtherLabel));
          },
        ),
      ]),
    );
  }
}

/// One whole-row switch with its one-line label. The rules text lives in the "?" sheet.
class _AirRow extends StatelessWidget {
  const _AirRow({required this.rowKey, required this.label, required this.sub, required this.value, required this.onChanged});

  final String rowKey;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          toggled: value,
          label: label,
          hint: sub,
          onTap: () => onChanged(!value),
          excludeSemantics: true,
          child: InkWell(
            key: Key(rowKey),
            onTap: () => onChanged(!value),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.phone_android_outlined, size: 20, color: p.tintInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 12, height: 1.35, color: p.mutedInk)),
                  ]),
                ),
                IgnorePointer(child: Switch(key: Key('${rowKey}Switch'), value: value, onChanged: (_) {})),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
