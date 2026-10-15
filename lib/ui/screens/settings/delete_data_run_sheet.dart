import 'package:flutter/material.dart';

import '../../../data/maintenance/delete_data_service.dart';
import '../../copy/delete_data_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/error_notes.dart';
import '../../widgets/tap_target.dart';
import 'delete_data_sheet.dart' show DeleteLevel;

/// §SETTINGS.DELETE_RUN — runs the confirmed delete and shows the busy state
/// and every result (0.1.2 S9b-2, DD2 + CB6 + addendum A3, A5, A9).
///
/// The sheet is its own route (no drag): while the run is in progress Back and
/// a tap outside do nothing (`PopScope`); after a result, Back or Done close it.

/// Shows the run sheet and starts the run at once. [hostContext] is the Settings
/// row's context: it is handed to [restart] BEFORE any await after a finished
/// reset, and never used again (the whole app is rebuilt).
Future<void> showDeleteRunSheet(
  BuildContext context, {
  required DeleteDataService service,
  required DeleteLevel level,
  required Future<bool> Function(BuildContext) restart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => DeleteRunSheet(service: service, level: level, restart: restart, hostContext: context),
  );
}

enum _Phase { busy, done, nothingDeleted, notFinished, busyElsewhere, resetNeedsReopen }

class DeleteRunSheet extends StatefulWidget {
  const DeleteRunSheet({
    super.key,
    required this.service,
    required this.level,
    required this.restart,
    required this.hostContext,
  });

  final DeleteDataService service;
  final DeleteLevel level;
  final Future<bool> Function(BuildContext) restart;
  final BuildContext hostContext;

  @override
  State<DeleteRunSheet> createState() => _DeleteRunSheetState();
}

class _DeleteRunSheetState extends State<DeleteRunSheet> {
  _Phase _phase = _Phase.busy;

  bool get _level1 => widget.level == DeleteLevel.transactions;

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// "Try again" calls this again: the SAME method for the same level.
  Future<void> _run() async {
    setState(() => _phase = _Phase.busy);
    DeleteDataResult r;
    try {
      r = _level1 ? await widget.service.deleteMyTransactions() : await widget.service.resetApp();
    } catch (_) {
      r = const DeleteDataResult(outcome: DeleteDataOutcome.notFinished);
    }
    if (!mounted) return;
    switch (r.outcome) {
      case DeleteDataOutcome.done:
        if (_level1) {
          setState(() => _phase = _Phase.done);
          return;
        }
        // Level 2: the soft restart rebuilds the whole app, this sheet with
        // it. The host context is handed over now and nothing here touches a
        // context or setState after a true answer (A9).
        // ignore: use_build_context_synchronously
        final restarted = await widget.restart(widget.hostContext);
        if (restarted || !mounted) return;
        setState(() => _phase = _Phase.resetNeedsReopen);
      case DeleteDataOutcome.nothingWasDeleted:
        setState(() => _phase = _Phase.nothingDeleted);
      case DeleteDataOutcome.notFinished:
        setState(() => _phase = _Phase.notFinished);
      case DeleteDataOutcome.busy:
        setState(() => _phase = _Phase.busyElsewhere);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final busy = _phase == _Phase.busy;
    return PopScope(
      canPop: !busy,
      child: BottomSheetShell(
        palette: palette,
        children: switch (_phase) {
          _Phase.busy => [
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _level1 ? kDeleteBusyLevel1 : kDeleteBusyLevel2,
                      key: const Key('deleteBusy'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _Phase.done => _result(palette, kDeleteDoneTitle, [
            kDeleteStayBackups,
            kDeleteStayAutoList,
            kDeleteStaySms,
            kDeleteLevel1SafetyGone,
            kDeleteLevel1CategoriesStay,
          ]),
          _Phase.nothingDeleted => _result(palette, kDeleteNothingDeletedTitle, const [kDeleteNothingDeletedBody], info: true),
          _Phase.notFinished => _failure(palette, [
            kDeleteDataNotFinished,
            if (!_level1) kDeleteLevel2NotFinishedExtra,
          ]),
          _Phase.busyElsewhere => _failure(palette, const [kDataOpBusy]),
          _Phase.resetNeedsReopen => _result(palette, kDeleteResetDoneReopen, const [
            kDeleteLevel2BackupsForget,
            kDeleteStaySms,
          ]),
        },
      ),
    );
  }

  List<Widget> _result(AppPalette palette, String title, List<String> lines, {bool info = false}) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(info ? Icons.info_outline : Icons.check_circle_outline, color: palette.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              title,
              key: const Key('deleteResultTitle'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink),
            ),
          ),
        ),
      ],
    ),
    for (final l in lines) Text(l, style: TextStyle(fontSize: 13, height: 1.45, color: palette.ink)),
    _actions(tryAgain: false),
  ];

  List<Widget> _failure(AppPalette palette, List<String> lines) => [
    for (final l in lines) ErrorBox(l),
    _actions(tryAgain: true),
  ];

  Widget _actions({required bool tryAgain}) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (tryAgain) ...[
        OutlinedButton(
          key: const Key('deleteTryAgain'),
          onPressed: _run,
          style: OutlinedButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
          child: const Text(kDeleteTryAgain),
        ),
        const SizedBox(width: 10),
      ],
      FilledButton(
        key: const Key('deleteDoneButton'),
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
        child: const Text(kDeleteDone),
      ),
    ],
  );
}
