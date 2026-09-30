import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/counterparty_dao.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../domain/cash/cash_code.dart';
import '../../../domain/counterparty/counterparty_key.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../shell/app_messenger.dart';
import '../../shell/chrome_widgets.dart';
import '../../shell/primary_shell.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/coach_tour.dart';
import 'amount_field.dart';
import 'category_chips.dart';
import 'details_card.dart';
import 'paste_card.dart';
import 'receiver_card.dart';
import 'review_bar.dart';
import 'review_sheet.dart';
import 'type_pills.dart';

/// T27 — Add rework (v0.1.0), locked to prototype v14
/// (the approved onboarding mock's Add screen):
/// paste-first M-Pesa entry, inline category chips (replacing the earlier
/// suggestion pill), and a "Check before saving" review sheet (replacing
/// the earlier separate confirmation page).
///
/// Add's coach-tour page id (the seen flag is `tour_seen_add`).
const addTourId = 'add';

/// Reached from the primary FAB (`Routes.add`) — a pushed page, never a
/// bottom-nav tab (Add is the FAB, never a
/// tab). Follows [AppPalette.of] (T27, superseding T26's one carve-out)
/// with a seamless top bar, the title "Add" and a round close.
class AddScreen extends StatefulWidget {
  const AddScreen({super.key, this.db});

  /// Test-only injection seam, threaded down to every DAO call this screen
  /// makes directly and to `category_chips.dart`/`review_sheet.dart`. `null`
  /// (the real route table) resolves the genuine on-device database.
  final Database? db;

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  // §ADD.SHELL.STATE — every field the mock's own `A` state object holds,
  // grounded in this codebase's real DAOs/types instead of the mock's
  // sample-data model.
  Database? _db;
  bool _loadingDb = true;

  /// `'MPESA'` or `'CASH'` — the top segmented switch.
  String _src = 'MPESA';

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'` — meaningless while
  /// [_src] is `'CASH'`.
  String _type = 'SEND_MONEY';

  /// True once a paste has successfully filled the form (D2's old "Type
  /// lock", carried forward as "the paste card/type pills stop being
  /// shown/built at all" — see `paste_card.dart`/`type_pills.dart`'s own
  /// doc comments).
  bool _filled = false;

  /// D4 — `'SMS_PARSE'` or `'MANUAL'`: how the CURRENT entry began. Later
  /// edits never change it.
  String _rawParseSource = 'MANUAL';

  final _amountController = TextEditingController();
  final _codeController = TextEditingController();
  final _feeController = TextEditingController();
  final _nameController = TextEditingController();
  final _subController = TextEditingController();

  DateTime _occurredAt = DateTime.now();

  /// D3 — "Also record …", a REMEMBERED preference across entries
  /// (`AppPrefs.readCaptureIdentityPreference`/`writeCaptureIdentityPreference`),
  /// default ticked the first time. A parse never changes it.
  bool _captureIdentity = true;

  /// D5 — whether [_codeController]'s current (shape-valid) value already
  /// matches a recorded non-Cash, non-deleted transaction.
  bool _codeDuplicate = false;

  int? _classificationId;
  String? _classificationName;

  /// The counterparty key the "Always use" tick is currently held for
  /// (`null` = not ticked). Applied on save only if it still equals the key
  /// derived at save time, so a stale tick is never applied to a different
  /// counterparty.
  String? _autoApplyKey;

  // Coach-tour anchors.
  final _pasteTourKey = GlobalKey();
  final _segTourKey = GlobalKey();
  final _receiverTourKey = GlobalKey();
  final _categoryTourKey = GlobalKey();

  /// Sends the user to the Paid to tab (Add is pushed over the shell).
  void _goToPaidTo() {
    final shell = PrimaryShell.active;
    if (shell != null) {
      Navigator.of(context).popUntil((route) => route == shell.route);
      shell.select(3);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(Routes.paidTo, (route) => false);
    }
  }

  List<CoachStep> _tourSteps() {
    final categoryStep = CoachStep(
      target: _categoryTourKey,
      text: 'Pick a category. Tick Always use to remember it for this receiver.',
      onEnter: () => scrollIntoView(_categoryTourKey),
    );
    if (_src == 'CASH') {
      return [
        CoachStep(target: _segTourKey, text: 'Switch back to M-Pesa to paste a message.'),
        categoryStep,
      ];
    }
    return [
      CoachStep(
        target: _pasteTourKey,
        text: 'Paste an M-Pesa message and we fill the form in. You check it before saving.',
      ),
      CoachStep(target: _segTourKey, text: 'Paid in cash? Switch to Cash.'),
      CoachStep(
        target: _receiverTourKey,
        text: 'Record the receiver’s name and phone to see this person on Paid to.',
        actionLabel: 'Take me there',
        onAction: _goToPaidTo,
        onEnter: () => scrollIntoView(_receiverTourKey),
      ),
      categoryStep,
    ];
  }

  void _replayTour() => CoachTour.start(context, pageId: addTourId, steps: _tourSteps());

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _codeController.dispose();
    _feeController.dispose();
    _nameController.dispose();
    _subController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    final capturePreference = await AppPrefs.readCaptureIdentityPreference();
    if (!mounted) return;
    setState(() {
      _db = db;
      _captureIdentity = capturePreference;
      _loadingDb = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: addTourId, steps: _tourSteps());
    });
  }

  // §ADD.SHELL.PARSE — paste-first M-Pesa entry (build step 3).

  void _onParsed(ParsedSmsFields fields) {
    setState(() {
      _type = fields.sourceType.dbValue;
      _filled = true;
      _rawParseSource = 'SMS_PARSE';
      _codeController.text = fields.code;
      _amountController.text = (fields.amountCents / 100).toStringAsFixed(2);
      _feeController.text = (fields.transactionCostCents / 100).toStringAsFixed(2);
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(fields.transactionOccurredAt);
      _nameController.text = fields.counterpartyLabel ?? '';
      _subController.text = fields.counterpartyPhone ?? fields.paybillAccountNumber ?? '';
      // A classification chosen for a previous (possibly different) Type's
      // group can't carry over — category_chips.dart re-offers a suggestion
      // if this counterparty is already known.
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
    });
    _checkCodeDuplicate();
  }

  void _startOver() {
    setState(() {
      _filled = false;
      _rawParseSource = 'MANUAL';
      _codeController.clear();
      _amountController.clear();
      _feeController.clear();
      _nameController.clear();
      _subController.clear();
      _occurredAt = DateTime.now();
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
      _codeDuplicate = false;
    });
  }

  void _onSrcChanged(String src) {
    if (src == _src) return;
    setState(() {
      _src = src;
      // Matches the mock's own tab-switch handler: only the classification
      // resets — amount/When/receiver fields carry over untouched, so
      // switching tabs to correct a mistake never throws away what's typed.
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
    });
  }

  void _onTypeChanged(String next) {
    if (next == _type) return;
    setState(() {
      _type = next;
      // A classification chosen under the previous Type's group would
      // violate the group-scope guard trigger for the new Type — must be
      // re-picked (same reasoning `mpesa_tab_body.dart` documented).
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
      _nameController.clear();
      _subController.clear();
    });
  }

  void _setCaptureIdentity(bool value) {
    setState(() => _captureIdentity = value);
    AppPrefs.writeCaptureIdentityPreference(value);
  }

  // §ADD.SHELL.CODE — D1/D5 Code field validity + duplicate check.

  static final RegExp _codeShapeRe = RegExp(r'^[A-Z0-9]{10}$');

  bool get _codeValidShape => _codeShapeRe.hasMatch(_codeController.text.trim());

  Future<void> _checkCodeDuplicate() async {
    final db = _db;
    if (db == null) return;
    final code = _codeController.text.trim();
    if (!_codeShapeRe.hasMatch(code)) {
      if (_codeDuplicate) setState(() => _codeDuplicate = false);
      return;
    }
    final exists = await TransactionDao.mpesaCodeExists(db, code: code);
    if (!mounted || _codeController.text.trim() != code) return;
    if (_codeDuplicate != exists) setState(() => _codeDuplicate = exists);
  }

  void _onCodeChanged(String _) {
    setState(() {});
    _checkCodeDuplicate();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (time == null || !mounted) return;
    setState(() => _occurredAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  // §ADD.SHELL.DERIVED — amounts, the counterparty key, gating.

  int? _parsedAmountCents() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  /// An empty Fee is `0`, not invalid (2026-09-19 PM decision, carried
  /// forward from `mpesa_tab_body.dart`'s identical rule).
  int? _parsedFeeCents() {
    final text = _feeController.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  String? get _effectiveLabel {
    if (!_captureIdentity) return null;
    final t = _nameController.text.trim();
    return t.isEmpty ? null : t;
  }

  String? get _effectivePhone {
    if (_type != 'SEND_MONEY' || !_captureIdentity) return null;
    final t = _subController.text.trim();
    return t.isEmpty ? null : t;
  }

  String? get _effectiveAccount {
    if (_type != 'PAYBILL' || !_captureIdentity) return null;
    final t = _subController.text.trim();
    return t.isEmpty ? null : t;
  }

  SmsSourceType get _currentSmsSourceType => switch (_type) {
        'SEND_MONEY' => SmsSourceType.sendMoney,
        'PAYBILL' => SmsSourceType.payBill,
        'BUY_GOODS' => SmsSourceType.buyGoods,
        _ => throw StateError('AddScreen._type must be a non-cash source type, got "$_type"'),
      };

  /// The single derivation call site shared by the read path (fed to
  /// `category_chips.dart`) and the write path (`_save`'s
  /// `CounterpartyDao.upsertOnConfirm` call) — same discipline
  /// `mpesa_tab_body.dart` established, carried forward unchanged.
  String _currentCounterpartyKey() {
    if (_src == 'CASH') return '';
    switch (_currentSmsSourceType) {
      case SmsSourceType.sendMoney:
        final phone = _effectivePhone;
        if (phone == null || phone.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);
      case SmsSourceType.payBill:
        final label = _effectiveLabel;
        final account = _effectiveAccount;
        if (label == null || label.isEmpty || account == null || account.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.payBill, counterpartyLabel: label, paybillAccountNumber: account);
      case SmsSourceType.buyGoods:
        final label = _effectiveLabel;
        if (label == null || label.isEmpty) return '';
        return deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: label);
    }
  }

  bool get _identityPairComplete {
    if (_src == 'CASH') return true; // Cash has no receiver fields (`_type` is only the M-Pesa side's)
    if (_type == 'SEND_MONEY' && _captureIdentity) {
      return _nameController.text.trim().isNotEmpty && _subController.text.trim().isNotEmpty;
    }
    if (_type == 'PAYBILL' && _captureIdentity) {
      return _nameController.text.trim().isNotEmpty && _subController.text.trim().isNotEmpty;
    }
    return true;
  }

  /// Build step 7: "disabled until there is an amount, a valid code
  /// (M-Pesa) and a category."
  List<String> get _missing {
    final miss = <String>[];
    if (_parsedAmountCents() == null) miss.add('an amount');
    if (_src == 'MPESA' && !_codeValidShape) miss.add('the 10-character code');
    if (_classificationId == null) miss.add('a category');
    return miss;
  }

  bool get _canReview =>
      _missing.isEmpty && !(_src == 'MPESA' && _codeDuplicate) && _identityPairComplete && _parsedFeeCents() != null;

  String get _reviewHint {
    if (_src == 'MPESA' && _codeDuplicate) return 'That code is already recorded.';
    final miss = _missing;
    if (miss.isEmpty) return '';
    if (miss.length == 1) return 'Add ${miss.first}.';
    return 'Add ${miss.sublist(0, miss.length - 1).join(', ')} and ${miss.last}.';
  }

  // §ADD.SHELL.SAVE — the sticky "Review & save" bar + "Check before
  // saving" sheet (build step 7). Nothing is written to `transactions`
  // until the sheet's own explicit "Confirm & save" tap.

  Future<void> _openReview() async {
    if (!_canReview) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReviewSheet(
        isCash: _src == 'CASH',
        typeLabel: _typeLabel,
        amountCents: _parsedAmountCents()!,
        counterpartyRowLabel: _reviewCounterpartyRowLabel(),
        counterpartyRowValue: _reviewCounterpartyRowValue(),
        whenText: formatLowKeyDateTime(_occurredAt),
        code: _codeController.text.trim(),
        feeCents: _src == 'MPESA' ? _parsedFeeCents() : null,
        categoryName: _classificationName!,
        alwaysForThem: _autoApplyKey != null && _autoApplyKey == _currentCounterpartyKey(),
        onConfirm: _save,
      ),
    );
    if (saved == true && mounted) {
      PrimaryShell.active?.dataChanged(); // Home / Analytics / Paid to re-query
      Navigator.of(context).pop();
      appMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  String get _typeLabel => switch (_src == 'CASH' ? 'CASH' : _type) {
        'SEND_MONEY' => 'Send Money',
        'PAYBILL' => 'Paybill',
        'BUY_GOODS' => 'Buy Goods',
        _ => 'Cash',
      };

  String get _counterpartyFieldLabel => switch (_type) {
        'PAYBILL' => 'Business',
        'BUY_GOODS' => 'Shop',
        _ => 'To',
      };

  /// Mock's `aReview.onclick`: `if (m && !A.who) rows.push(['Receiver', 'Not
  /// recorded (private)'])` — a distinct, generic label from the per-type
  /// one used when a name WAS captured.
  String? _reviewCounterpartyRowLabel() {
    if (_src == 'CASH') return null;
    if (!_captureIdentity) return 'Receiver';
    return _nameController.text.trim().isEmpty ? null : _counterpartyFieldLabel;
  }

  String? _reviewCounterpartyRowValue() {
    if (_src == 'CASH') return null;
    if (!_captureIdentity) return 'Not recorded (private)';
    final name = _nameController.text.trim();
    if (name.isEmpty) return null;
    final sub = _subController.text.trim();
    return sub.isEmpty ? name.toUpperCase() : '${name.toUpperCase()} · $sub';
  }

  /// The real save — the same DAO writes as today (`TransactionDao.insert`,
  /// then `CounterpartyDao.upsertOnConfirm`/`setAutoApply` if applicable).
  /// Returns `null` on success, an error message on failure — `review_sheet
  /// .dart` owns showing that message inline; this method owns no UI.
  Future<String?> _save() async {
    final db = _db;
    if (db == null) return 'Not ready yet — try again.';
    final cash = _src == 'CASH';
    final input = NewTransactionInput(
      displayCode: cash ? generateCashDisplayCode(_occurredAt.millisecondsSinceEpoch) : _codeController.text.trim(),
      sourceType: cash ? 'CASH' : _type,
      amountCents: _parsedAmountCents()!,
      transactionCostCents: cash ? null : _parsedFeeCents(),
      counterpartyLabel: cash ? null : _effectiveLabel,
      counterpartyPhone: cash ? null : _effectivePhone,
      paybillAccountNumber: cash ? null : _effectiveAccount,
      classificationId: _classificationId!,
      rawParseSource: cash ? 'MANUAL' : _rawParseSource,
      transactionOccurredAt: _occurredAt.millisecondsSinceEpoch,
    );
    try {
      await TransactionDao.insert(db, input);
    } on DatabaseException catch (e) {
      return 'Could not save this transaction: $e';
    }
    if (!cash) {
      final key = _currentCounterpartyKey();
      final classificationId = _classificationId;
      if (key.isNotEmpty && classificationId != null) {
        try {
          await CounterpartyDao.upsertOnConfirm(db, sourceType: _type, counterpartyKey: key, classificationId: classificationId);
          if (_autoApplyKey == key) {
            await CounterpartyDao.setAutoApply(db, sourceType: _type, counterpartyKey: key);
          }
        } catch (_) {
          // The transaction row is already committed — a counterparty-memory
          // failure shouldn't block the "Saved" confirmation.
        }
      }
    }
    return null;
  }

  // §ADD.SHELL.BUILD

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scaffold = Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(),
        foregroundColor: palette.ink, // the back arrow: the default is dark on the dark palettes
        systemOverlayStyle: palette.systemOverlayStyle,
        title: Text('Add', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: palette.ink)),
        centerTitle: false,
        actions: [
          if (!_loadingDb) ...[
            IconCircleButton(
              key: const Key('pageHelpButton'),
              icon: Icons.help_outline_rounded,
              tooltip: 'Show tips for this page',
              background: palette.card,
              foreground: palette.ink,
              onTap: _replayTour,
            ),
            const SizedBox(width: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconCircleButton(
              key: const Key('addCloseButton'),
              icon: Icons.close,
              tooltip: 'Close',
              background: palette.card, // `surface` equals the page in the dark palettes
              foreground: palette.ink,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      body: _loadingDb ? const Center(child: CircularProgressIndicator()) : _buildBody(palette),
    );
    // Same rule `PrimaryScaffold` established for any primary page pushed
    // over the live shell: Android back from Add lands the shell on Home,
    // like back from any non-Home tab.
    final overShell = PrimaryShell.active;
    if (overShell == null) return scaffold;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) overShell.select(0);
      },
      child: scaffold,
    );
  }

  Widget _buildBody(AppPalette palette) {
    final db = _db!;
    final counterpartyKey = _currentCounterpartyKey();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: KeyedSubtree(
            key: _segTourKey,
            child: _SrcSegment(src: _src, onChanged: _onSrcChanged),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_src == 'MPESA') ...[
                  PasteCard(
                    filled: _filled,
                    onParsed: _onParsed,
                    onStartOver: _startOver,
                    tourKey: _pasteTourKey,
                  ),
                  if (!_filled) ...[
                    const SizedBox(height: 14),
                    TypePills.orDivider(palette),
                    const SizedBox(height: 10),
                    TypePills(type: _type, onChanged: _onTypeChanged),
                  ],
                ],
                AmountField(controller: _amountController, onChanged: (_) => setState(() {})),
                if (_src == 'MPESA')
                  DetailsCard(
                    code: _codeController,
                    fee: _feeController,
                    codeShapeInvalid: _codeController.text.trim().isNotEmpty && !_codeValidShape,
                    codeDuplicate: _codeValidShape && _codeDuplicate,
                    whenText: formatLowKeyDateTime(_occurredAt),
                    onCodeChanged: _onCodeChanged,
                    onFeeChanged: (_) => setState(() {}),
                    onWhenChangeTap: _pickDateTime,
                  )
                else
                  CashWhenRow(whenText: formatLowKeyDateTime(_occurredAt), onWhenChangeTap: _pickDateTime),
                if (_src == 'MPESA')
                  KeyedSubtree(
                    key: _receiverTourKey,
                    child: ReceiverCard(
                      type: _type,
                      checked: _captureIdentity,
                      name: _nameController,
                      sub: _subController,
                      onCheckedChanged: _setCaptureIdentity,
                      onFieldChanged: () => setState(() {}),
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.ink)),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: _categoryTourKey,
                  child: CategoryChips(
                    db: db,
                    sourceType: _src == 'CASH' ? 'CASH' : _type,
                    counterpartyKey: counterpartyKey,
                    counterpartyDisplayName: _nameController.text.trim(),
                    selectedId: _classificationId,
                    selectedName: _classificationName,
                    onSelected: (id, name) => setState(() {
                      _classificationId = id;
                      _classificationName = name;
                    }),
                    autoApplyChecked: _autoApplyKey != null && _autoApplyKey == counterpartyKey,
                    onAutoApplyChanged: (checked) => setState(() => _autoApplyKey = checked ? counterpartyKey : null),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        ReviewBar(enabled: _canReview, hint: _reviewHint, onTap: _openReview),
      ],
    );
  }
}

class _SrcSegment extends StatelessWidget {
  const _SrcSegment({required this.src, required this.onChanged});

  final String src;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // In the dark palettes `track` and `surface` equal the page colour, so the
    // toggle would be invisible: use the card colour for the track there.
    final dark = palette.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: dark ? palette.card : palette.track, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _segment(context, palette, 'M-Pesa', 'MPESA')),
          Expanded(child: _segment(context, palette, 'Cash', 'CASH')),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, AppPalette palette, String label, String value) {
    final active = src == value;
    return GestureDetector(
      key: Key('addSrcSeg_$value'),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? (palette.brightness == Brightness.dark ? palette.line : palette.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? palette.ink : palette.mutedInk),
        ),
      ),
    );
  }
}

