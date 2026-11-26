/// §AUTOREAD.LEVELS.SETUP_SHEET: the Set up sheet (0.2.2 item 2, slice U-SETUP; mock-remembered-v2 setup-half,
/// setup-full, setup-sm, setup-pb, setup-bg, setup-search, chk-rtl-p; sign-off "Set up sheet"). Title
/// "Set up a recipient"; opens at three quarters of the screen and drags (or, by its handle button, taps) to
/// full; a back arrow at the top left, no X. Under the title: the search (names only, F2: never hidden digits,
/// levels_search.dart), the type chips (setup_type_chips.dart; Airtime only as a link, PM Q3) and the rows
/// (setup_row.dart). The list comes from [SetupRecipientsSource] (read once per open and again after each
/// person sheet closes, so a new level tag shows). A row tap calls [SetupSheet.onPick] (I2 opens the person
/// sheet there); when it returns, the focus goes back to that row. Loading, error and empty states use existing
/// words; while "Record receiver details" is OFF the source answers empty, so the sheet shows the empty line.
/// Screens import this; this file imports the section widgets.
library;

import 'package:flutter/material.dart';

import '../../../ui/shell/chrome_widgets.dart';
import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'levels_copy.dart' show kLevelsEmpty, kLevelsLoadFailed;
import 'levels_search.dart';
import 'setup_ports.dart';
import 'setup_row.dart';
import 'setup_type_chips.dart';

// WORDING-MISSING -> W2: the spoken name of the loading circle (no visible text).
const String _kTodoSetUpLoading = '[PM to write: Set up list is loading]';

/// The sheet's sizes, as parts of the screen height: it opens at [kSetupSheetStart]; [kSetupSheetFull] is
/// full; dragged down to [kSetupSheetMin] it closes.
const double kSetupSheetStart = 0.75;
const double kSetupSheetFull = 1.0;
const double kSetupSheetMin = 0.3;

/// Opens the Set up sheet over [context]. [onPick]: a row was tapped (I2 opens the person sheet; the sheet waits
/// for it, reads the list again and puts the focus back on the row). [onAirtime]: the Airtime chip's link
/// (null = no Airtime chip); the sheet closes first, then calls it.
Future<void> showSetupSheet(
  BuildContext context, {
  required SetupRecipientsSource source,
  required Future<void> Function(SetupRecipient recipient) onPick,
  VoidCallback? onAirtime,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SetupSheet(source: source, onPick: onPick, onAirtime: onAirtime),
  );
}

class SetupSheet extends StatefulWidget {
  const SetupSheet({super.key, required this.source, required this.onPick, this.onAirtime});
  final SetupRecipientsSource source;
  final Future<void> Function(SetupRecipient recipient) onPick;
  final VoidCallback? onAirtime;

  @override
  State<SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<SetupSheet> {
  final _drag = DraggableScrollableController();
  final _query = TextEditingController();
  final Map<String, FocusNode> _nodes = {};
  List<SetupRecipient>? _all;
  bool _failed = false;
  bool _busy = false;
  bool _full = false;
  ReceiverType? _type;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _drag.dispose();
    _query.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  static String _id(SetupRecipient r) => '${r.type.code}.${r.key}';

  FocusNode _node(SetupRecipient r) => _nodes.putIfAbsent(_id(r), FocusNode.new);

  Future<void> _load() async {
    final gen = ++_gen;
    try {
      final list = await widget.source.list();
      if (!mounted || gen != _gen) return;
      setState(() {
        _all = list;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _pick(SetupRecipient r) async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onPick(r);
    } catch (_) {
      // The person sheet's own errors are its own; the list stays.
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[_id(r)]?.requestFocus();
    });
  }

  void _airtime() {
    final go = widget.onAirtime;
    if (go == null) return;
    Navigator.of(context).pop();
    go();
  }

  void _toggleSize() {
    if (!_drag.isAttached) return;
    _drag.animateTo(_full ? kSetupSheetStart : kSetupSheetFull,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _dragBy(DragUpdateDetails d) {
    if (!_drag.isAttached) return;
    final next = (_drag.size - _drag.pixelsToSize(d.primaryDelta ?? 0)).clamp(kSetupSheetMin, kSetupSheetFull);
    _drag.jumpTo(next);
  }

  void _dragEnd(DragEndDetails d) {
    if (!_drag.isAttached) return;
    final s = _drag.size;
    if (s < (kSetupSheetMin + kSetupSheetStart) / 2) {
      Navigator.of(context).maybePop();
      return;
    }
    final to = s >= (kSetupSheetStart + kSetupSheetFull) / 2 ? kSetupSheetFull : kSetupSheetStart;
    _drag.animateTo(to, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          final full = n.extent >= kSetupSheetFull - 0.01;
          if (full != _full) setState(() => _full = full);
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _drag,
          expand: false,
          initialChildSize: kSetupSheetStart,
          minChildSize: kSetupSheetMin,
          maxChildSize: kSetupSheetFull,
          snap: true,
          snapSizes: const [kSetupSheetStart],
          builder: (context, scroll) => Container(
            key: const Key('setupSheet'),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _handle(p),
                _header(p),
                Expanded(child: _body(p, scroll)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The handle: drag it, or tap it (a button: "Make the list taller" / "Make the list shorter").
  Widget _handle(AppPalette p) => Semantics(
        button: true,
        label: _full ? kHardSheetShorter : kHardSheetTaller,
        excludeSemantics: true,
        onTap: _toggleSize,
        child: GestureDetector(
          key: const Key('setupHandle'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggleSize,
          onVerticalDragUpdate: _dragBy,
          onVerticalDragEnd: _dragEnd,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ),
      );

  Widget _header(AppPalette p) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 16, 4),
        child: Row(children: [
          IconCircleButton(
            key: const Key('setupBack'),
            icon: Icons.arrow_back, // follows the text direction (points right in RTL)
            tooltip: kHardBack,
            background: p.track,
            foreground: p.ink,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(kHardSetUpTitle,
                  key: const Key('setupTitle'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.ink)),
            ),
          ),
        ]),
      );

  Widget _body(AppPalette p, ScrollController scroll) {
    final all = _all ?? const <SetupRecipient>[];
    final q = _query.text;
    final matched = [for (final r in all) if (setupRecipientMatches(r, q)) r];
    final counts = <ReceiverType, int>{};
    for (final r in matched) {
      counts[r.type] = (counts[r.type] ?? 0) + 1;
    }
    final shown = _type == null ? matched : [for (final r in matched) if (r.type == _type) r];
    final hint = TextStyle(fontSize: 13, height: 1.35, color: p.mutedInk);

    final Widget state;
    if (_failed) {
      state = _note(p, kLevelsLoadFailed, const Key('setupFailed'));
    } else if (_all == null) {
      state = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Semantics(
            label: _kTodoSetUpLoading,
            liveRegion: true,
            child: const CircularProgressIndicator(key: Key('setupLoading')),
          ),
        ),
      );
    } else if (all.isEmpty) {
      state = _note(p, kLevelsEmpty, const Key('setupEmpty'));
    } else if (shown.isEmpty) {
      state = _note(p, kHardSearchEmpty, const Key('setupNoMatch'));
    } else {
      state = const SizedBox.shrink();
    }

    return CustomScrollView(
      key: const Key('setupScroll'),
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: LevelsSearchField(
            fieldKey: const Key('setupSearch'),
            controller: _query,
            onChanged: (_) => setState(() {}),
          ),
        ),
        SliverToBoxAdapter(
          child: SetupTypeChips(
            selected: _type,
            counts: counts,
            total: matched.length,
            onSelect: (t) => setState(() => _type = t),
            onAirtime: widget.onAirtime == null ? null : _airtime,
          ),
        ),
        if (all.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 6),
              child: Text(kHardSetUpHint, key: const Key('setupHint'), style: hint),
            ),
          ),
        SliverToBoxAdapter(child: state),
        SliverList.separated(
          itemCount: shown.length,
          separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: p.line),
          itemBuilder: (_, i) {
            final r = shown[i];
            return SetupRow(
              key: Key('setupRow.${_id(r)}'),
              recipient: r,
              focusNode: _node(r),
              onTap: () => _pick(r),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }

  /// A state line (error, empty, no match), read out when it appears.
  Widget _note(AppPalette p, String text, Key key) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Text(text, key: key, style: TextStyle(fontSize: 14, height: 1.4, color: p.softInk)),
        ),
      );
}
