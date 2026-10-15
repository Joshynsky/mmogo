import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/backup/auto_backup_service.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/classification_dao.dart';
import '../../../data/db/counterparty_dao.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../data/prefs/recipient_memory.dart';
import '../../../domain/cash/cash_code.dart';
import '../../../domain/format/ksh_amount.dart';
import '../../../domain/parsing/name_only_fields.dart';
import '../../../domain/parsing/name_only_resolver.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../shell/app_messenger.dart';
import '../../shell/chrome_widgets.dart';
import '../../shell/primary_shell.dart';
import '../../theme/app_colors.dart';
import '../../widgets/coach_tour.dart';
import '../../widgets/ksh_input_formatter.dart';
import 'add_draft.dart';
import 'add_tour.dart';
import 'amount_field.dart';
import 'category_section.dart';
import 'details_card.dart';
import 'fee_hint.dart';
import 'name_only_ask.dart';
import 'name_only_state.dart';
import 'paste_card.dart';
import 'receiver_card.dart';
import 'recipient_chooser.dart';
import 'review_bar.dart';
import 'review_sheet.dart';
import 'src_segment.dart';
import 'type_pills.dart';

export 'add_tour.dart' show addTourId;

/// T27 — Add rework (v0.1.0), locked to prototype v14
/// (the approved onboarding mock's Add screen):
/// paste-first M-Pesa entry, inline category chips (replacing the earlier
/// suggestion pill), and a "Check before saving" review sheet (replacing
/// the earlier separate confirmation page).
///
/// Reached from the primary FAB (`Routes.add`) — a pushed page, never a
/// bottom-nav tab (Add is the FAB, never a
/// tab). Follows [AppPalette.of] (T27, superseding T26's one carve-out)
/// with a seamless top bar, the title "Add" and a round close.
class AddScreen extends StatefulWidget {
  const AddScreen({super.key, this.db, this.memory});

  /// Test-only injection seam, threaded down to every DAO call this screen
  /// makes directly and to `category_chips.dart`/`review_sheet.dart`. `null`
  /// (the real route table) resolves the genuine on-device database.
  final Database? db;

  /// Test-only injection seam for the remembered Pochi / Send Money answers
  /// (0.1.2 S8c-2). `null` uses the real device-only store; the screen holds ONE
  /// instance for its whole life.
  final RecipientMemory? memory;

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

  /// One of the six M-Pesa `source_type` values (`'SEND_MONEY'`, `'PAYBILL'`,
  /// `'BUY_GOODS'`, `'POCHI_LA_BIASHARA'`, `'AGENT_WITHDRAWAL'`, `'AIRTIME'`) —
  /// meaningless while [_src] is `'CASH'`.
  String _type = 'SEND_MONEY';

  /// True once a paste has successfully filled the form (D2's "Type lock"):
  /// the six pills stay visible but locked (the parsed one open) until Start
  /// over, and the "or enter it yourself" divider goes.
  bool _filled = false;

  /// Withdrawal: the Fee field was edited or left, so its empty-error may show.
  bool _feeTouched = false;

  /// A parsed agent number that was not 1..20 digits: the field stays empty and
  /// shows an inline error (it must never reach the database check).
  bool _agentNumberRejected = false;

  /// 0.1.2 S8c-2 (NO4): the name-only message state (pending type, tick, how,
  /// the SMS name and its key), the one memory instance, and a counter that
  /// makes a late lookup result of an older parse harmless.
  final _ask = NameOnlyState();
  late final RecipientMemory _memory = widget.memory ?? RecipientMemory();
  int _parseGen = 0;

  /// Remembered recipients chooser: the whole list, loaded once when typing
  /// starts, and the plain "Type changed to X" status line.
  List<RecipientEntry>? _memoryList;
  bool _memoryLoading = false;
  String _swNote = '';

  /// Set by `_save` when remembering the answer pushed the oldest name out.
  bool _droppedOldest = false;

  final _feeFocus = FocusNode();
  final _scroll = ScrollController();

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

  List<CoachStep> _tourSteps() => addTourSteps(
        cash: _src == 'CASH',
        pasteKey: _pasteTourKey,
        segKey: _segTourKey,
        receiverKey: _receiverTourKey,
        categoryKey: _categoryTourKey,
        onGoToPaidTo: () => goToPaidToFromAdd(context),
        hasReceiver: !_draft.isAirtime,
      );

  void _replayTour() => CoachTour.start(context, pageId: addTourId, steps: _tourSteps());

  @override
  void initState() {
    super.initState();
    _feeFocus.addListener(() {
      if (!_feeFocus.hasFocus && !_feeTouched && mounted) setState(() => _feeTouched = true);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _feeFocus.dispose();
    _scroll.dispose();
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
    final agent = fields.agentNumber;
    final agentOk = agent == null || AddDraft.agentNumberOk(agent);
    _parseGen++;
    setState(() {
      _ask.reset();
      _swNote = '';
      _src = 'MPESA';
      _type = fields.sourceType.dbValue;
      _filled = true;
      _rawParseSource = 'SMS_PARSE';
      _feeTouched = false;
      _codeController.text = fields.code;
      _amountController.text = groupKshText((fields.amountCents / 100).toStringAsFixed(2));
      // Airtime has no Fee field: its parsed fee is kept here, silently.
      _feeController.text = (fields.transactionCostCents / 100).toStringAsFixed(2);
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(fields.transactionOccurredAt);
      _nameController.text = fields.counterpartyLabel ?? '';
      _subController.text =
          fields.counterpartyPhone ?? fields.paybillAccountNumber ?? (agentOk ? (agent ?? '') : '');
      _agentNumberRejected = !agentOk;
      // A classification chosen for a previous (possibly different) Type's
      // group can't carry over — category_chips.dart re-offers a suggestion
      // if this counterparty is already known.
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
    });
    _checkCodeDuplicate();
    _ensureFixedCategory();
    // The mock scrolls the page back to the top after a parse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  /// Start over: clears the fields, unlocks the pills and puts the type back on
  /// Send Money (the mock's `A = {...blank(), src: A.src}`).
  void _startOver() {
    _parseGen++;
    setState(() {
      _ask.reset();
      _swNote = '';
      _filled = false;
      _type = 'SEND_MONEY';
      _rawParseSource = 'MANUAL';
      _feeTouched = false;
      _agentNumberRejected = false;
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

  // §ADD.SHELL.NAMEONLY — 0.1.2 S8c-2 (NO4): a name-only message, the ask, the
  // remembered answer and the remembered recipients chooser.

  /// A name-only message fills everything that does not depend on the type
  /// (code, amount, fee, When) at once, with the type still UNDECIDED
  /// ([_ask].pending); then memory is asked, and on a miss the ask opens. This
  /// runs after the paste sheet has closed.
  void _onNameOnly(NameOnlyFields f) {
    final gen = ++_parseGen;
    setState(() {
      _ask.start(name: f.name, key: deriveRecipientNameKey(f.name));
      _swNote = '';
      _src = 'MPESA';
      _type = 'SEND_MONEY'; // a neutral value while undecided; the pills show none selected
      _filled = true;
      _rawParseSource = 'SMS_PARSE';
      _feeTouched = false;
      _agentNumberRejected = false;
      _codeController.text = f.code;
      _amountController.text = groupKshText((f.amountCents / 100).toStringAsFixed(2));
      _feeController.text = (f.transactionCostCents / 100).toStringAsFixed(2);
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(f.transactionOccurredAt);
      _nameController.clear();
      _subController.clear();
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
    });
    _checkCodeDuplicate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
    _resolveNameOnly(f, gen);
  }

  Future<void> _resolveNameOnly(NameOnlyFields f, int gen) async {
    RecipientRule? rule;
    try {
      // Looked up whatever the receiver-details switch says (F2 is decided in S9);
      // an error or a timeout counts as a miss, so the ask opens.
      rule = await _memory.lookup(_ask.key).timeout(const Duration(seconds: 3));
    } catch (_) {
      rule = null;
    }
    if (!mounted || gen != _parseGen) return;
    switch (resolveNameOnly(f, rule)) {
      case Resolved(:final fields):
        _applyAnswer(fields.sourceType, how: 'memory', rule: rule);
      case NeedsType():
        await _openAsk();
    }
  }

  Future<void> _openAsk({bool change = false}) async {
    if (!_ask.active) return;
    final gen = _parseGen;
    if (change) _ask.tick = false; // the mock: Change reopens the ask with the tick OFF
    final current = _ask.pending ? null : _draft.smsSourceType;
    final picked = await showNameOnlyAsk(
      context,
      name: _ask.name,
      current: current,
      showTick: _captureIdentity,
      change: current != null,
      tick: _ask.tick,
      onTick: (v) => _ask.tick = v,
    );
    // Closed without a choice (Back, scrim, Esc, swipe) or the same type: nothing changes.
    if (!mounted || gen != _parseGen || picked == null || picked == current) return;
    _applyAnswer(picked, how: 'chosen');
  }

  void _applyAnswer(SmsSourceType type, {required String how, RecipientRule? rule}) {
    setState(() {
      _ask.pending = false;
      _ask.how = how;
      if (how == 'memory') {
        _ask.remembered = rule;
        _ask.tick = false; // "Remember this change" starts OFF
      }
      _type = type.dbValue;
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
      _nameController.text = _ask.name; // the SMS name, for Pochi's label / Send Money's note
      _subController.clear();
      _feeTouched = false;
    });
  }

  /// Written only AFTER the transaction is saved, and only when the live
  /// switch, the tick and the rules in [NameOnlyState.shouldRemember] all say so.
  /// Never throws; returns true when the oldest remembered name was dropped.
  Future<bool> _rememberAnswer() async {
    final type = _draft.smsSourceType;
    if (!_ask.shouldRemember(captureOn: _captureIdentity, type: type)) return false;
    try {
      final r = await _memory
          .remember(_ask.key, type, recordDetailsOn: _captureIdentity)
          .timeout(const Duration(seconds: 4));
      return r == RememberResult.savedDroppedOldest;
    } catch (_) {
      return false;
    }
  }

  bool get _chooserOn =>
      _src == 'MPESA' && !_filled && _captureIdentity && (_type == 'SEND_MONEY' || _type == 'POCHI_LA_BIASHARA');

  void _onNameTyped() {
    setState(() => _swNote = '');
    if (_memoryList == null && !_memoryLoading && _chooserOn && _nameController.text.trim().isNotEmpty) {
      _memoryLoading = true;
      _loadMemoryList();
    }
  }

  Future<void> _loadMemoryList() async {
    List<RecipientEntry> list;
    try {
      list = await _memory.list().timeout(const Duration(seconds: 3));
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() {
      _memoryList = list;
      _memoryLoading = false;
    });
  }

  /// A chooser tap: set the type FIRST (changing it clears the Name), then the
  /// Name. Never writes to memory.
  void _pickRecipient(RecipientEntry e) {
    final switchType = e.rule.type.dbValue != _type;
    _onTypeChanged(e.rule.type.dbValue);
    setState(() {
      _nameController.text = e.key;
      _swNote = switchType ? recipientTypeChangedText(e.key, e.rule.type) : '';
    });
  }

  Widget? _chooserBelowName() {
    final list = _memoryList;
    final entries = _chooserOn && list != null
        ? recipientChooserEntries(list, typed: _nameController.text, currentType: _draft.smsSourceType)
        : const <RecipientEntry>[];
    if (entries.isEmpty && _swNote.isEmpty) return null;
    return RecipientChooser(entries: entries, onPick: _pickRecipient, note: _swNote);
  }

  void _useUsualFee(int usualCents) {
    setState(() {
      _feeController.text = feeHintFieldText(usualCents);
      _feeTouched = true;
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
    _ensureFixedCategory();
  }

  void _onTypeChanged(String next) {
    if (next == _type || _filled) return;
    setState(() {
      _swNote = '';
      _type = next;
      // A classification chosen under the previous Type's group would
      // violate the group-scope guard trigger for the new Type — must be
      // re-picked (same reasoning `mpesa_tab_body.dart` documented).
      _classificationId = null;
      _classificationName = null;
      _autoApplyKey = null;
      // The receiver fields (and so an agent number) never carry to another type.
      _nameController.clear();
      _subController.clear();
      _feeTouched = false;
      _agentNumberRejected = false;
      // Airtime has no Fee field: nothing typed for another type is kept.
      if (next == 'AIRTIME') _feeController.clear();
    });
    _ensureFixedCategory();
  }

  /// Withdrawal and Airtime use their built-in category, found by `seed_key`
  /// and pre-selected; the user cannot change it.
  Future<void> _ensureFixedCategory() async {
    final db = _db;
    final type = _type;
    final seed = AddDraft.fixedSeedKey(type);
    if (db == null || seed == null || _src == 'CASH') return;
    final item = await ClassificationDao.fetchActiveBySeedKey(db, seedKey: seed);
    if (!mounted || item == null || _type != type || _src == 'CASH') return;
    setState(() {
      _classificationId = item.id;
      _classificationName = item.name;
    });
  }

  void _setCaptureIdentity(bool value) {
    setState(() => _captureIdentity = value);
    AppPrefs.writeCaptureIdentityPreference(value);
  }

  // §ADD.SHELL.CODE — D1/D5 Code field validity + duplicate check.

  Future<void> _checkCodeDuplicate() async {
    final db = _db;
    if (db == null) return;
    final code = _codeController.text.trim();
    if (!AddDraft.codeShapeOk(code)) {
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

  // §ADD.SHELL.DERIVED — the rules live in add_draft.dart (§ADD.DRAFT).

  AddDraft get _draft => AddDraft(
        src: _src,
        type: _type,
        captureIdentity: _captureIdentity,
        amountText: _amountController.text,
        feeText: _feeController.text,
        codeText: _codeController.text,
        nameText: _nameController.text,
        subText: _subController.text,
        codeDuplicate: _codeDuplicate,
        classificationId: _classificationId,
      );

  int? _parsedAmountCents() => _draft.amountCents;
  int? _parsedFeeCents() => _draft.feeCents;
  String _currentCounterpartyKey() => _draft.counterpartyKey;
  bool get _canReview => !_ask.pending && _draft.canReview;

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
        typeLabel: _draft.typeLabel,
        amountCents: _parsedAmountCents()!,
        counterpartyRowLabel: _draft.reviewCounterpartyRowLabel,
        counterpartyRowValue: _draft.reviewCounterpartyRowValue,
        whenText: formatLowKeyDateTime(_occurredAt),
        code: _codeController.text.trim(),
        feeCents: _src == 'MPESA' && !_draft.isAirtime ? _parsedFeeCents() : null,
        categoryName: _classificationName!,
        alwaysForThem: _autoApplyKey != null && _autoApplyKey == _currentCounterpartyKey(),
        onConfirm: _save,
      ),
    );
    if (saved == true && mounted) {
      PrimaryShell.active?.dataChanged(); // Home / Analytics / Paid to re-query
      Navigator.of(context).pop();
      // S8c-2: a suffix on "Saved" (one snackbar), never a name.
      final note = _droppedOldest ? 'Saved. The oldest remembered name was removed to make room.' : 'Saved';
      appMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(note)));
    }
  }

  /// The real save — the same DAO writes as today (`TransactionDao.insert`,
  /// then `CounterpartyDao.upsertOnConfirm`/`setAutoApply` if applicable).
  /// Returns `null` on success, an error message on failure — `review_sheet
  /// .dart` owns showing that message inline; this method owns no UI.
  Future<String?> _save() async {
    final db = _db;
    if (db == null) return 'Not ready yet — try again.';
    final cash = _src == 'CASH';
    final draft = _draft;
    try {
      final input = draft.toInput(
        cashCode: generateCashDisplayCode(_occurredAt.millisecondsSinceEpoch),
        rawParseSource: _rawParseSource,
        occurredAtMillis: _occurredAt.millisecondsSinceEpoch,
      );
      await TransactionDao.insert(db, input);
    } catch (_) {
      // B4: any failure (a DatabaseException, or anything else thrown while
      // building or writing the row) comes back as this plain message, which
      // the review sheet shows inline; the screen never crashes or sticks on
      // "saving". The raw error text means nothing to the user.
      return 'Could not save this transaction. Check the amount and code, then try again.';
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
    // S8c-2 (NO4): the transaction is committed; only now is the answer
    // remembered (never on cancel or a failed insert; not for Cash).
    _droppedOldest = !cash && await _rememberAnswer();
    // B20: the entry is saved. Count it for auto-backup (inert when it is
    // off; never throws; never awaited, so a slow or failing backup cannot
    // hold up or fail this save).
    AutoBackupService.instance.onEntrySaved().ignore();
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
            child: SrcSegment(src: _src, onChanged: _onSrcChanged),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_src == 'MPESA') ...[
                  PasteCard(
                    filled: _filled,
                    onParsed: _onParsed,
                    onNameOnly: _onNameOnly,
                    onStartOver: _startOver,
                    tourKey: _pasteTourKey,
                  ),
                  if (_ask.active && _filled) ...[
                    const SizedBox(height: 10),
                    if (_ask.pending)
                      NameOnlyAwaitRow(onChoose: _openAsk)
                    else
                      NameOnlyMarker(
                        remembered: _ask.how == 'memory',
                        typeName: _draft.typeLabel,
                        sendMoney: _type == 'SEND_MONEY',
                        onChange: () => _openAsk(change: true),
                      ),
                  ],
                  // After a parse the six pills stay (the parsed one open, the rest
                  // dimmed and locked); only the divider goes.
                  if (!_filled) ...[
                    const SizedBox(height: 14),
                    TypePills.orDivider(palette),
                  ],
                  const SizedBox(height: 10),
                  TypePills(type: _ask.pending ? null : _type, locked: _filled, onChanged: _onTypeChanged),
                ],
                AmountField(
                  controller: _amountController,
                  onChanged: (_) => setState(() {}),
                  errorText: _amountController.text.trim().isNotEmpty && _parsedAmountCents() == null ? kshAmountHelp : null,
                ),
                if (_src == 'MPESA')
                  DetailsCard(
                    code: _codeController,
                    fee: _feeController,
                    codeShapeInvalid: _codeController.text.trim().isNotEmpty && !_draft.codeValidShape,
                    codeDuplicate: _draft.codeValidShape && _codeDuplicate,
                    whenText: formatLowKeyDateTime(_occurredAt),
                    onCodeChanged: _onCodeChanged,
                    onFeeChanged: (_) => setState(() => _feeTouched = true),
                    onWhenChangeTap: _pickDateTime,
                    noFee: _draft.isAirtime,
                    feeError: _draft.feeError(touched: _feeTouched),
                    feeFocus: _feeFocus,
                    underFee: _draft.isWithdrawal && !_ask.pending
                        ? FeeHint(amountCents: _parsedAmountCents(), feeText: _feeController.text, onUse: _useUsualFee)
                        : null,
                  )
                else
                  CashWhenRow(whenText: formatLowKeyDateTime(_occurredAt), onWhenChangeTap: _pickDateTime),
                if (_src == 'MPESA' && !_draft.isAirtime && !_ask.pending)
                  KeyedSubtree(
                    key: _receiverTourKey,
                    child: ReceiverCard(
                      type: _type,
                      checked: _captureIdentity,
                      name: _nameController,
                      sub: _subController,
                      onCheckedChanged: _setCaptureIdentity,
                      onFieldChanged: () => setState(() => _agentNumberRejected = false),
                      onNameChanged: _onNameTyped,
                      belowName: _chooserBelowName(),
                      subError: _agentNumberRejected && _type == 'AGENT_WITHDRAWAL'
                          ? 'Agent number: digits only, up to 20. Enter it yourself.'
                          : null,
                    ),
                  ),
                if (!_ask.pending)
                  CategorySection(
                    db: db,
                    fixed: _draft.hasFixedCategory,
                    fixedLabel: _draft.typeLabel,
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
                    tourKey: _categoryTourKey,
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        ReviewBar(
          enabled: _canReview,
          hint: _ask.pending ? kNameOnlyChooseLine : _draft.reviewHint,
          onTap: _openReview,
        ),
      ],
    );
  }
}
