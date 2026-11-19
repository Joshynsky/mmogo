import 'package:flutter/material.dart';

import '../../data/db/classification_dao.dart' show classificationNameMaxLength;
import '../copy/withdrawal_copy.dart';
import 'error_notes.dart';
import '../theme/app_colors.dart';

/// One category the user can pick for a withdrawal.
class WdChoice {
  const WdChoice(this.id, this.name);
  final int id;
  final String name;
}

/// Result of creating a category from the "+ New" chip: the new id and the reloaded
/// choices, or an error message to show under the field.
class WdCreateResult {
  const WdCreateResult.ok(int this.id, List<WdChoice> this.choices) : error = null;
  const WdCreateResult.error(String this.error) : id = null, choices = null;
  final int? id;
  final List<WdChoice>? choices;
  final String? error;
}

/// §WIDGET.WITHDRAWAL_USE_BLOCK (0.2.1) — "What was this money for?": a dashed
/// "Cash only" chip first, then the category chips, then one grey sentence.
/// Shared by the Analytics withdrawal sheet, Add (type W) and the Notifications
/// Categorize sheet. [selectedId] null = Cash only. [onChanged] gets null for Cash only.
class WithdrawalUseBlock extends StatefulWidget {
  const WithdrawalUseBlock({
    super.key,
    required this.palette,
    required this.choices,
    required this.selectedId,
    required this.onChanged,
    required this.sentence,
    this.noteUnder,
    this.enabled = true,
    this.showQuestion = true,
    this.showCashOnly = true,
    this.onCreate,
  });

  final AppPalette palette;
  final List<WdChoice> choices;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String sentence;

  /// A muted second sentence under the chips (e.g. "Changing the category here ...").
  final String? noteUnder;
  final bool enabled;
  final bool showQuestion;

  /// False in the linked-entry sheet: an entry always has a category (Cash only is on the withdrawal).
  final bool showCashOnly;

  /// When set, a "+ New" chip ends the list. Creates the category, refreshes [choices] in the
  /// caller, and returns its id (selected via [onChanged]) or an error message.
  final Future<WdCreateResult> Function(String name)? onCreate;

  @override
  State<WithdrawalUseBlock> createState() => _WithdrawalUseBlockState();
}

class _WithdrawalUseBlockState extends State<WithdrawalUseBlock> {
  bool _creating = false;
  bool _busy = false;
  String? _error;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final create = widget.onCreate;
    if (create == null || _busy) return;
    _busy = true;
    setState(() => _error = null);
    final r = await create(_name.text);
    _busy = false;
    if (!mounted) return;
    if (r.id == null) {
      setState(() => _error = r.error);
      return;
    }
    _name.clear();
    setState(() => _creating = false);
    widget.onChanged(r.id);
  }

  Widget _newChip(AppPalette p) => Semantics(
        button: true,
        label: '+ New',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('wdChipNew'),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: widget.enabled ? () => setState(() => _creating = true) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(999)), border: Border.all(color: p.primary, width: 1.5)),
                child: Text('+ New', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.primary)),
              ),
            ),
          ),
        ),
      );

  Widget _newRow(AppPalette p) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('wdNewField'),
                    controller: _name,
                    maxLength: classificationNameMaxLength,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: TextStyle(color: p.ink),
                    cursorColor: p.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'New category name',
                      hintStyle: TextStyle(color: p.mutedInk),
                      border: OutlineInputBorder(borderSide: BorderSide(color: p.line)),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: p.line)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('wdNewAdd'),
                  onPressed: _add,
                  style: FilledButton.styleFrom(backgroundColor: p.primary, foregroundColor: p.onPrimary),
                  child: const Text('Add'),
                ),
              ],
            ),
            if (_error != null)
              KeyedSubtree(key: const Key('wdNewError'), child: FieldError(_error!, padding: const EdgeInsets.only(top: 6, left: 2))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final choices = widget.choices;
    final selectedId = widget.selectedId;
    final enabled = widget.enabled;
    final onChanged = widget.onChanged;
    final showQuestion = widget.showQuestion;
    final showCashOnly = widget.showCashOnly;
    final noteUnder = widget.noteUnder;
    final sentence = widget.sentence;
    Widget chip({required Key key, required String label, required bool on, required bool dashed, required VoidCallback onTap}) {
      final bg = on ? p.primary : p.track;
      final fg = on ? p.onPrimary : p.ink;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  border: dashed && !on ? Border.all(color: p.mutedInk, width: 1.3) : null,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: enabled ? fg : p.mutedInk)),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showQuestion)
          Text(kWdQuestion, key: const Key('wdQuestion'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
        if (showQuestion) const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 0,
          children: [
            if (showCashOnly) chip(key: const Key('wdChipCashOnly'), label: kWdCashOnly, on: selectedId == null, dashed: true, onTap: () => onChanged(null)),
            for (final c in choices)
              chip(key: Key('wdChip-${c.id}'), label: c.name, on: selectedId == c.id, dashed: false, onTap: () => onChanged(c.id)),
            if (widget.onCreate != null && !_creating) _newChip(p),
          ],
        ),
        if (widget.onCreate != null && _creating) _newRow(p),
        if (noteUnder != null) ...[
          const SizedBox(height: 6),
          Text(noteUnder, key: const Key('wdNoteUnder'), style: TextStyle(fontSize: 11, height: 1.45, color: p.mutedInk)),
        ],
        if (sentence.isNotEmpty) const SizedBox(height: 6),
        if (sentence.isNotEmpty) Semantics(
          liveRegion: true,
          child: Text(sentence, key: const Key('wdSentence'), style: TextStyle(fontSize: 11, height: 1.45, color: p.softInk)),
        ),
      ],
    );
  }
}
