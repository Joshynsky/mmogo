/// §AUTOREAD.CATEGORIZE_SHEET — the bottom sheet a waiting row's Categorize
/// action opens (signed mock `ui-rework/notifications.html`, "Categorizing").
///
/// Autoread flavor only: it lives under `lib/autoread/ui/` and is reached from
/// shared code only inside `if (kAutoReadCompiled)`. It shows the parsed
/// details read-only, the categories as chips, and a "+ New" pill that makes a
/// new category the same way the Add screen's "+ New" pill does (through
/// [CategoryChoices]). Save stays disabled until a category is chosen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/error_notes.dart';
import '../model/waiting_item.dart';
import 'category_choices.dart';
import 'notifications_autoread_copy.dart';
import 'categorize_copy.dart';
import 'categorize_details.dart';

export 'categorize_copy.dart';


/// Opens the sheet. [onSave] gets the chosen category id once; the sheet
/// closes after it completes. Close, scrim and Back close without saving.
Future<void> showCategorizeSheet(
  BuildContext context, {
  required WaitingItem item,
  required CategoryChoices choices,
  required Future<void> Function(String categoryId) onSave,
  Future<List<CategoryChoice>> Function()? suggestedChips,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        CategorizeSheet(item: item, choices: choices, onSave: onSave, suggestedChips: suggestedChips),
  );
}

class CategorizeSheet extends StatefulWidget {
  const CategorizeSheet({
    super.key,
    required this.item,
    required this.choices,
    required this.onSave,
    this.suggestedChips,
  });

  final WaitingItem item;
  final CategoryChoices choices;
  final Future<void> Function(String categoryId) onSave;

  /// 0.2.2: the suggested chips for this item, left to right (most used last); null or empty or a failure =
  /// no chips and no label (the list as before). Read when the sheet opens.
  final Future<List<CategoryChoice>> Function()? suggestedChips;

  @override
  State<CategorizeSheet> createState() => _CategorizeSheetState();
}

class _CategorizeSheetState extends State<CategorizeSheet> {
  List<CategoryChoice> _cats = const [];
  List<CategoryChoice> _suggested = const [];
  bool _loading = true;
  String? _loadError;
  String? _pickedId;
  bool _creatingNew = false;
  bool _busyCreate = false;
  String? _newError;
  bool _saving = false;
  String? _saveError;
  final _newController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cats = await widget.choices.categories();
      if (!mounted) return;
      setState(() {
        _cats = cats;
        // Row 17: an airtime item has exactly one category, its own kind's; it is preselected.
        if (_isAirtime && cats.length == 1) _pickedId = cats.first.id;
        _loading = false;
      });
      _loadChips(cats);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = kCategorizeLoadFailed;
        _loading = false;
      });
    }
  }

  /// The Suggested row arrives after the list is shown (the list never waits for the history); any failure
  /// leaves the list as it is, with no chips and no label.
  Future<void> _loadChips(List<CategoryChoice> cats) async {
    if (widget.suggestedChips == null || _isAirtime) return;
    try {
      final chips = await widget.suggestedChips!();
      if (!mounted) return;
      final s = splitSuggested(cats, chips).suggested;
      if (s.isNotEmpty) setState(() => _suggested = s);
    } catch (_) {
      // never an error: the full list as today
    }
  }

  bool get _isAirtime => widget.item.parsed?.sourceType == SmsSourceType.airtime;

  CategoryChoice? get _picked {
    for (final c in _cats) {
      if (c.id == _pickedId) return c;
    }
    return null;
  }

  Future<void> _addNew() async {
    if (_busyCreate) return;
    _busyCreate = true;
    final name = _newController.text.trim();
    try {
      final made = await widget.choices.create(name);
      if (!mounted) return;
      final cats = await widget.choices.categories();
      if (!mounted) return;
      setState(() {
        _cats = cats.any((c) => c.id == made.id) ? cats : [...cats, made];
        _pickedId = made.id;
        _creatingNew = false;
        _newError = null;
        _newController.clear();
      });
    } on CategoryNameError catch (e) {
      if (!mounted) return;
      setState(() {
        _newError = switch (e.reason) {
          CategoryNameReason.empty => kCategorizeEmptyName,
          CategoryNameReason.duplicate => categorizeDuplicate(name),
          CategoryNameReason.tooLong => kCategorizeTooLong,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _newError = kCategorizeNewFailed);
    } finally {
      _busyCreate = false;
    }
  }

  Future<void> _save() async {
    final id = _pickedId;
    if (id == null || _saving) return;
    _saving = true;
    setState(() => _saveError = null);
    try {
      await widget.onSave(id);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      _saving = false;
      if (mounted) setState(() => _saveError = kCategorizeSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.viewInsets.bottom, mq.viewPadding.bottom);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.88,
            ),
            child: Material(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: kActionCategorize,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: ExcludeSemantics(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    CategorizeHeader(palette: palette),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CategorizeDetails(item: widget.item, palette: palette),
                            const SizedBox(height: 14),
                            if (_suggested.isNotEmpty) ...[
                              categorizeLabel(palette, kCategorizeSuggestedLabel),
                              const SizedBox(height: 8),
                              Wrap(
                                key: const Key('categorizeSuggestedRow'),
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (var i = 0; i < _suggested.length; i++)
                                    _chip(palette, _suggested[i], mostUsed: i == _suggested.length - 1),
                                ],
                              ),
                              const SizedBox(height: 14),
                              categorizeLabel(palette, kCategorizeAllLabel),
                            ] else
                              categorizeLabel(palette, kCategorizeCategoryLabel),
                            const SizedBox(height: 8),
                            _chips(palette),
                            if (_creatingNew) _newRow(palette),
                            const SizedBox(height: 14),
                            if (_saveError != null)
                              FieldError(
                                _saveError!,
                                padding: const EdgeInsets.only(bottom: 8),
                              ),
                            _saveButton(palette),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Every category not already shown in the Suggested row (no repeats).
  List<CategoryChoice> get _restCats {
    if (_suggested.isEmpty) return _cats;
    final ids = {for (final c in _suggested) c.id};
    return [for (final c in _cats) if (!ids.contains(c.id)) c];
  }

  Widget _chips(AppPalette palette) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null)
          FieldError(_loadError!, padding: const EdgeInsets.only(bottom: 8)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _restCats) _chip(palette, c, fixed: _isAirtime),
            if (!_creatingNew && !_isAirtime) _newPill(palette),
          ],
        ),
        if (_isAirtime && !_loading && _loadError == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              kCategorizeAirtimeFixed,
              key: const Key('categorizeAirtimeFixed'),
              style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
            ),
          ),
      ],
    );
  }

  Widget _chip(AppPalette palette, CategoryChoice c, {bool fixed = false, bool mostUsed = false}) {
    final selected = c.id == _pickedId;
    // A fixed chip (airtime) is shown selected and cannot be switched.
    void tap() {
      if (!fixed) setState(() => _pickedId = c.id);
    }
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: c.name,
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        color: selected ? palette.primary : palette.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected || mostUsed ? palette.primary : palette.line,
            width: 1.5,
          ),
        ),
        child: InkWell(
          key: Key('categorizeChip_${c.id}'),
          customBorder: const StadiumBorder(),
          onTap: fixed ? null : tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check, size: 16, color: palette.onPrimary),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? palette.onPrimary : palette.ink,
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

  Widget _newPill(AppPalette palette) {
    void tap() => setState(() => _creatingNew = true);
    return Semantics(
      button: true,
      label: kCategorizeNewPill,
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        shape: StadiumBorder(
          side: BorderSide(color: palette.primary, width: 1.5),
        ),
        child: InkWell(
          key: const Key('categorizeNewPill'),
          customBorder: const StadiumBorder(),
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  kCategorizeNewPill,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _newRow(AppPalette palette) {
    final hasError = _newError != null;
    final border = hasError ? palette.error : palette.line;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('categorizeNewField'),
                  controller: _newController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  maxLength: kCategoryNameMaxLength,
                  // Over-long text is not cut off: it shows the error instead.
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  style: TextStyle(color: palette.ink),
                  cursorColor: palette.primary,
                  onChanged: (_) {
                    if (_newError != null) setState(() => _newError = null);
                  },
                  onSubmitted: (_) => _addNew(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: kCategorizeNewHint,
                    hintStyle: TextStyle(color: palette.mutedInk),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: hasError ? palette.error : palette.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
                child: FilledButton(
                  key: const Key('categorizeNewAdd'),
                  onPressed: _addNew,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.onPrimary,
                    minimumSize: const Size(64, 48),
                  ),
                  child: const Text(kCategorizeNewAdd),
                ),
              ),
            ],
          ),
          if (hasError)
            KeyedSubtree(
              key: const Key('categorizeNewError'),
              child: FieldError(
                _newError!,
                padding: const EdgeInsets.only(top: 6, left: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _saveButton(AppPalette palette) {
    final picked = _picked;
    final label = picked == null
        ? kCategorizeChoosePrompt
        : categorizeSaveIn(picked.name);
    return FilledButton(
      key: const Key('categorizeSave'),
      onPressed: picked == null ? null : _save,
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        disabledBackgroundColor: palette.track,
        disabledForegroundColor: palette.mutedInk,
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}
