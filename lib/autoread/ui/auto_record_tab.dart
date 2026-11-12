/// §AUTOREAD.AUTO_RECORD_TAB: the second tab of the Remembered page (chip row,
/// two airtime rows, the opened explainer block). It reads and flips
/// the ONE shared controller it is given, so the Notifications card and this
/// tab always agree. Nothing is stored here: the controller writes the two
/// existing switches.
library;

import 'package:flutter/material.dart';

import '../../ui/screens/remembered/remembered_extra_tab.dart';
import '../../ui/theme/app_colors.dart';
import '../logic/airtime_auto.dart';
import 'airtime_kind_copy.dart' show kAirKindMyselfLabel, kAirKindOtherLabel;
import 'auto_record_copy.dart';

/// The page object the Remembered screen takes as its second tab.
RememberedExtraTab autoRecordExtraTab(AirtimeAutoController controller) =>
    _AutoRecordExtraTab(controller);

class _AutoRecordExtraTab implements RememberedExtraTab {
  _AutoRecordExtraTab(this.c);
  final AirtimeAutoController c;

  @override
  Listenable get listenable => c;
  @override
  String get pageTitle => kAutoRecordPageTitle;
  @override
  String get recipientsTabLabel => kAutoRecordRecipientsTab;
  @override
  String tabLabel() => autoRecordTabLabel((c.on ? 1 : 0) + (c.onOther ? 1 : 0));
  @override
  String get forgetAllLabel => kAutoRecordForgetAllLabel;
  @override
  String get forgetAllNote => kAutoRecordForgetAllNote;
  @override
  Widget buildBody(BuildContext context) => AutoRecordTab(controller: c);
}

/// The tab body. Own number first, then the other number.
class AutoRecordTab extends StatelessWidget {
  const AutoRecordTab({super.key, required this.controller});
  final AirtimeAutoController controller;

  void _toast(BuildContext context, String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        key: const Key('autoRecordTab'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const _ChipRow(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Text(kAutoRecordLaterTypes,
                key: const Key('autoRecordLaterTypes'),
                style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
          ),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Semantics(
        container: true,
        label: kAutoRecordChipsGroup,
        child: Wrap(spacing: 5, runSpacing: 6, children: [
          Semantics(
            selected: true,
            label: kAutoRecordChipAirtime,
            excludeSemantics: true,
            child: Container(
              key: const Key('autoRecordChipAirtime'),
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(color: p.typeAirtime, borderRadius: BorderRadius.circular(999)),
              // Center with a width factor keeps the pill as wide as its text;
              // a Container alignment would stretch it to the full row.
              child: Center(
                widthFactor: 1,
                child: Text(kAutoRecordChipAirtime,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.onPillAirtime ?? p.onPrimary)),
              ),
            ),
          ),
          for (final (code, name) in kAutoRecordLaterChips)
            Semantics(
              enabled: false,
              label: autoRecordChipLaterSpoken(name),
              excludeSemantics: true,
              child: Opacity(
                opacity: .5,
                child: Container(
                  key: Key('autoRecordChip$code'),
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line, width: 1.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.softInk)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// One whole-row switch. When on, the panel opens under it.
class _AirRow extends StatelessWidget {
  const _AirRow({
    required this.rowKey,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

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
        if (value) _Panel(rowKey: rowKey, label: label),
      ],
    );
  }
}

/// The opened part: one explainer block, full width, left aligned with the row text.
class _Panel extends StatelessWidget {
  const _Panel({required this.rowKey, required this.label});
  final String rowKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      key: Key('${rowKey}Panel'),
      // 14 + 34 + 12: lines up with the row text.
      padding: const EdgeInsets.fromLTRB(60, 0, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(autoRecordExplainTap(label),
            key: Key('${rowKey}Explain'), style: TextStyle(fontSize: 12.5, height: 1.4, color: p.softInk)),
        const SizedBox(height: 4),
        Text(kAutoRecordExplainLater,
            key: Key('${rowKey}ExplainLater'), style: TextStyle(fontSize: 12, height: 1.35, color: p.mutedInk)),
      ]),
    );
  }
}
