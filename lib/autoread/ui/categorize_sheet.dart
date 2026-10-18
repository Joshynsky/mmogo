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

import '../../domain/format/money.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/error_notes.dart';
import '../model/waiting_item.dart';
import 'category_choices.dart';
import 'notifications_autoread_copy.dart';

// Strings. From the Add screen: hint, "Add", "+ New", duplicate text. From the
// signed mock: heading (kActionCategorize), "Category", "Choose a category to
// save", "Save in X", "Close", the 100-character text, the detail labels.
// NOT IN MOCK or Add (plainest words): the empty-name text, the two failure texts.
const String kCategorizeCategoryLabel = 'Category';
const String kCategorizeNewPill = '+ New';
const String kCategorizeNewHint = 'New category name';
const String kCategorizeNewAdd = 'Add';
const String kCategorizeClose = 'Close';
const String kCategorizeChoosePrompt = 'Choose a category to save';
String categorizeSaveIn(String name) => 'Save in $name';
const String kCategorizeTooLong =
    'A category name can be up to 100 characters.';
String categorizeDuplicate(String name) =>
    'A category named "$name" already exists.';
const String kCategorizeEmptyName =
    'Type a name for the category.'; // NOT IN MOCK
const String kCategorizeLoadFailed =
    'Could not load the categories.'; // NOT IN MOCK
const String kCategorizeNewFailed =
    'Could not create the category. Try again.'; // NOT IN MOCK
const String kCategorizeSaveFailed =
    'Could not save. Try again.'; // NOT IN MOCK
const String kCategorizeCheckThis = 'Check this one.'; // mock flag box
const String kCategorizeLabelType = 'Type';
const String kCategorizeLabelAmount = 'Amount';
const String kCategorizeLabelPaidTo = 'Paid to';
const String kCategorizeLabelDate = 'Date';
const String kCategorizeLabelCost = 'Transaction cost';

/// Opens the sheet. [onSave] gets the chosen category id once; the sheet
/// closes after it completes. Close, scrim and Back close without saving.
Future<void> showCategorizeSheet(
  BuildContext context, {
  required WaitingItem item,
  required CategoryChoices choices,
  required Future<void> Function(String categoryId) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        CategorizeSheet(item: item, choices: choices, onSave: onSave),
  );
}

class CategorizeSheet extends StatefulWidget {
  const CategorizeSheet({
    super.key,
    required this.item,
    required this.choices,
    required this.onSave,
  });

  final WaitingItem item;
  final CategoryChoices choices;
  final Future<void> Function(String categoryId) onSave;

  @override
  State<CategorizeSheet> createState() => _CategorizeSheetState();
}

class _CategorizeSheetState extends State<CategorizeSheet> {
  List<CategoryChoice> _cats = const [];
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
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = kCategorizeLoadFailed;
        _loading = false;
      });
    }
  }

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
                    _header(palette),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._details(palette),
                            const SizedBox(height: 14),
                            Text(
                              kCategorizeCategoryLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: palette.ink,
                              ),
                            ),
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

  Widget _header(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                kActionCategorize,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('categorizeClose'),
            tooltip: kCategorizeClose,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.close, color: palette.ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  List<Widget> _details(AppPalette palette) {
    final p = widget.item.parsed;
    final flagged = widget.item.sameCodeDifferentDetails;
    return [
      if (flagged)
        Container(
          key: const Key('categorizeFlag'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: palette.tintInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: kCategorizeCheckThis,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const TextSpan(text: ' $kFlaggedLine'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.tintInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (p != null)
        Container(
          key: const Key('categorizeDetails'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _detailRow(
                palette,
                kCategorizeLabelType,
                _typeLabel(p.sourceType),
              ),
              _detailRow(
                palette,
                kCategorizeLabelAmount,
                formatKsh(p.amountCents),
              ),
              _detailRow(
                palette,
                kCategorizeLabelPaidTo,
                p.counterpartyLabel ?? '—',
              ),
              _detailRow(
                palette,
                kCategorizeLabelDate,
                _dateTime(
                  DateTime.fromMillisecondsSinceEpoch(p.transactionOccurredAt),
                ),
              ),
              _detailRow(
                palette,
                kCategorizeLabelCost,
                formatKsh(p.transactionCostCents),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _detailRow(AppPalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: palette.mutedInk),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            for (final c in _cats) _chip(palette, c),
            if (!_creatingNew) _newPill(palette),
          ],
        ),
      ],
    );
  }

  Widget _chip(AppPalette palette, CategoryChoice c) {
    final selected = c.id == _pickedId;
    void tap() => setState(() => _pickedId = c.id);
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
            color: selected ? palette.primary : palette.line,
            width: 1.5,
          ),
        ),
        child: InkWell(
          key: Key('categorizeChip_${c.id}'),
          customBorder: const StadiumBorder(),
          onTap: tap,
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

String _typeLabel(SmsSourceType t) => switch (t) {
  SmsSourceType.sendMoney => 'Send Money',
  SmsSourceType.payBill => 'Paybill',
  SmsSourceType.buyGoods => 'Buy Goods',
  SmsSourceType.pochi => 'Pochi La Biashara',
  SmsSourceType.agentWithdrawal => 'Withdrawal',
  SmsSourceType.airtime => 'Airtime',
};

/// The mock's date text: `18-10-2026, 08:30`.
String _dateTime(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}-${p(d.month)}-${d.year}, ${p(d.hour)}:${p(d.minute)}';
}
