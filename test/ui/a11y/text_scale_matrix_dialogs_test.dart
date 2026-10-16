// S11b TS2 matrix, part 4: the dialogs (merge / restore, rejected file, could not
// restore, "Before you back up", Forget all remembered recipients, First day of
// the week). The Backup and Delete data SHEETS are covered by their own 1.3
// tests (see the matrix in _pipeline/v0.1.2/baseline/s11b-deviations.md).
// Fakes only: the dialogs are opened from a stub button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/restore_dialogs.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/screens/settings/look_section.dart';

import '../../support/a11y_matrix.dart';
import '../../support/fake_restore_service.dart';

Finder _k(String key) => find.byKey(Key(key));

Widget _opener(void Function(BuildContext) open) => Builder(
  builder: (c) => Scaffold(
    body: Center(
      child: TextButton(key: const Key('opener'), onPressed: () => open(c), child: const Text('OPEN')),
    ),
  ),
);

Future<void> _open(WidgetTester t) async {
  await t.tap(_k('opener'));
  await a11ySettle(t);
}

Finder _button(String label) => find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  tearDownAll(printA11yLog);

  a11ySubject(
    'Dialog: merge or replace a backup',
    home: () => _opener((c) => showMergeOrReplaceDialog(c, fakePreview())),
    open: _open,
    actions: () => [
      A11yAction('Merge option', _k('restoreOptionMerge')),
      A11yAction('Replace option', _k('restoreOptionReplace')),
      A11yAction('Cancel', _button('Cancel')),
      A11yAction('Continue', _k('restoreContinue')),
    ],
  );

  a11ySubject(
    'Dialog: backup file rejected',
    home: () => _opener((c) => showRestoreRejectDialog(c, 'This file is not a mmogo backup.')),
    open: _open,
    actions: () => [A11yAction('OK', _button('OK'))],
  );

  a11ySubject(
    'Dialog: could not restore',
    home: () => _opener((c) => showRestoreFailedDialog(c)),
    open: _open,
    actions: () => [A11yAction('OK', _button('OK'))],
  );

  a11ySubject(
    'Dialog: before you back up',
    home: () => _opener((c) => BackupExportFlow.confirm(c)),
    open: _open,
    actions: () => [
      A11yAction('Cancel', _button('Cancel')),
      A11yAction('Share backup', _button('Share backup')),
    ],
  );

  late RecipientMemory memory;
  a11ySubject(
    'Dialog: forget all remembered recipients',
    before: () async {
      var clock = 1000;
      memory = RecipientMemory(nowMs: () => clock++);
      await memory.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
      await memory.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
    },
    home: () => _opener(
      (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => RememberedScreen(memory: memory))),
    ),
    open: (t) async {
      await _open(t);
      await t.tap(_k('rememberedForgetAll'));
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Cancel', _k('forgetAllCancel')),
      A11yAction('Forget all', _k('forgetAllConfirm')),
    ],
  );

  a11ySubject(
    'Dialog: first day of the week',
    home: () => _opener((c) => showFirstDayDialog(c, current: 1)),
    open: _open,
    actions: () => [
      for (var d = 1; d <= 7; d++) A11yAction('Day $d', _k('firstDay-$d')),
      A11yAction('Cancel', _button('Cancel')),
    ],
  );
}
