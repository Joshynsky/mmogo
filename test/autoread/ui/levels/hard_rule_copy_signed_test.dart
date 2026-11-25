// Item 2 redesign, slice C1: pins the PM's signed words (ITEM2-REVIEW-SIGNOFF-2026-11-25, sections
// "Signed wording" and "Signed at sign-off") in hard_rule_copy.dart verbatim, the singular / plural of
// every counted line for 0, 1 and 2, and "limit" instead of "ceiling" in every value of the file.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';

void main() {
  group('signed lines, verbatim', () {
    // (the signed line with the sample values filled in, the value in hard_rule_copy.dart)
    final table = <String, (String, String)>{
      'no-tap message': ('Alice Wanjiru, Ksh 450 recorded as Family/Friends', hardAutoArrived('Alice Wanjiru', 45000, 'Family/Friends')),
      'pill auto': ('Bob set to Auto-record as Rent', hardPillAuto('Bob', 'Rent')),
      'pill any amount': ('Records any amount.', kHardPillAnyAmount),
      'pill set a limit': ('Set a limit', kHardPillSetLimit),
      'pill up to': ('Records up to Ksh 1,500.', hardPillUpTo(150000)),
      'pill change': ('Change', kHardPillChange),
      'pill ask first': ('Bob set to Ask first · Rent', hardPillAskFirst('Bob', 'Rent')),
      'pill suggested': ('Bob set to Suggested', hardPillSuggested('Bob')),
      'pause row (Settings)': ('Every Auto-record person is asked first until you resume.', kHardPauseSettingsSub),
      'pause row (page)': ('Every Auto-record person is asked first until you resume.', kHardPauseSub),
      'pinned notice title': ('Auto-record is paused', kHardPausedNoticeTitle),
      'pinned notice action': ('Resume', kHardResume),
      'reset title': ('Reset 3 people to Suggested?', hardResetTitle(3)),
      'reset body': (
        'They go back to Suggested and their limits are removed. mmogo still remembers them. Nothing already recorded changes.',
        kHardResetBody
      ),
      'reset ok': ('Reset', kHardResetOk),
      'forget title': ('Forget all 3 people?', hardForgetTitle(3)),
      'forget body': (
        "mmogo forgets their names, numbers and Auto-record settings. Nothing already recorded changes. This can't be undone.",
        kHardForgetBody
      ),
      'forget ok': ('Forget all', kHardForgetOk),
      'forget toast': ('Forgot 3 people.', hardForgetToast(3)),
      'restore toast': ('Backup restored. Check 3 Auto-record people.', hardRestoreToast(3)),
      'restore line': (
        '3 people were on Auto-record in your backup. They ask first until you check them.',
        hardReviewLine(3)
      ),
      'restore review button': ('Review', kHardReviewButton),
      'restore title': ('Auto-record from your backup', kHardReviewTitle),
      'restore sub': ('Tick who goes back on Auto-record. The rest ask first.', kHardReviewSub),
      'restore save': ('Save', kHardReviewConfirm),
      'restore keep all': ('Keep all on Ask first', kHardReviewKeepAll),
      'restore saved toast': ('3 people back on Auto-record.', hardReviewToast(3)),
      'restore kept toast': ('Everyone stays on Ask first.', kHardReviewKeptToast),
      'restore off title': ('Backup restored', kHardRestoreOffTitle),
      'restore off body': (
        'Settings for 3 people were left out because Record receiver details is off. '
            'Turn it on, then restore again to bring them back.',
        hardRestoreOffBody(3)
      ),
      'restore off button': ('Open Settings', kHardOpenSettings),
      'details-off card': (
        "Record receiver details is off, so mmogo doesn't use your saved people or record them for you. "
            'Your settings come back when you turn it on.',
        kHardDetailsOffCard
      ),
      'details-off button': ('Turn it on in Settings', kHardTurnOnInSettings),
      'paybill line': ('Paybill payments always ask first.', kHardPaybillAlwaysAsks),
      'suggest from': ('Suggest from:', kHardSuggestFrom),
      'last 10 payments': ('Last 10 payments', kHardSuggestLast10),
      'categories I choose': ('Categories I choose', kHardSuggestChoose),
      'how suggest works title': ('How Suggest works', kHardSuggestHowTitle),
      'how suggest works, last 10': (
        "When you pay Bob, the alert says Tap Parse. Then mmogo suggests the categories you used most in Bob's "
            'last 10 payments. Nothing records without a tap.',
        hardSuggestHowLast10('Bob')
      ),
      'how suggest works, chosen': (
        'When you pay Bob, the alert shows your categories as buttons straight away, with no Parse tap. '
            'Choose up to 2. Nothing records without a tap.',
        hardSuggestHowChosen('Bob', 2)
      ),
      'alert preview': ('Your alert will show:', kHardSuggestAlertPreview),
      'none chosen': ('None chosen yet', kHardSuggestNoneChosen),
      'must-choose error': ('Choose at least one category, or pick Last 10 payments.', kHardSuggestNeedOne),
      'undo pill': ('Undone. Bob stays on Auto-record.', hardUndoStays('Bob')),
      'pause pill': ('Auto-record paused. Your settings are kept.', kHardPausedToast),
      'page forget button': ('Forget all people', kHardForgetButton),
      'suggests from last 10': ('Suggests from last 10 payments', kHardSuggestsFromLast10),
      'set up title': ('Set up a recipient', kHardSetUpTitle),
      'set up button': ('Set up', kHardSetUpButton),
      'recently recorded': ('Recently recorded', kHardRecentlyRecorded),
      'auto-record tag': ('Auto-record', kHardAutoRecordTag),
    };
    for (final e in table.entries) {
      test(e.key, () => expect(e.value.$2, e.value.$1));
    }
  });

  group('singular and plural: 0, 1, 2', () {
    test('peopleCount', () {
      expect(peopleCount(0), '0 people');
      expect(peopleCount(1), '1 person');
      expect(peopleCount(2), '2 people');
    });
    // (function, [0, 1, 2] expected)
    final counted = <String, (String Function(int), List<String>)>{
      'hardPausedBanner': (
        hardPausedBanner,
        [
          'Auto-record is paused. 0 people are asked first until you resume.',
          'Auto-record is paused. 1 person is asked first until you resume.',
          'Auto-record is paused. 2 people are asked first until you resume.',
        ]
      ),
      'hardResumedToast': (
        hardResumedToast,
        ['Auto-record is back on for 0 people.', 'Auto-record is back on for 1 person.', 'Auto-record is back on for 2 people.']
      ),
      'hardResetTitle': (
        hardResetTitle,
        ['Reset 0 people to Suggested?', 'Reset 1 person to Suggested?', 'Reset 2 people to Suggested?']
      ),
      'hardResetToast': (
        hardResetToast,
        ['0 people reset to Suggested.', '1 person reset to Suggested.', '2 people reset to Suggested.']
      ),
      'hardForgetTitle': (hardForgetTitle, ['Forget all 0 people?', 'Forget all 1 person?', 'Forget all 2 people?']),
      'hardForgetToast': (hardForgetToast, ['Forgot 0 people.', 'Forgot 1 person.', 'Forgot 2 people.']),
      'hardReviewLine': (
        hardReviewLine,
        [
          '0 people were on Auto-record in your backup. They ask first until you check them.',
          '1 person was on Auto-record in your backup. They ask first until you check them.',
          '2 people were on Auto-record in your backup. They ask first until you check them.',
        ]
      ),
      'hardReviewToast': (
        hardReviewToast,
        ['0 people back on Auto-record.', '1 person back on Auto-record.', '2 people back on Auto-record.']
      ),
      'hardRestoreToast': (
        hardRestoreToast,
        [
          'Backup restored. Check 0 Auto-record people.',
          'Backup restored. Check 1 Auto-record person.',
          'Backup restored. Check 2 Auto-record people.',
        ]
      ),
      'hardRestoreOffBody': (
        hardRestoreOffBody,
        [
          'Settings for 0 people were left out because Record receiver details is off. Turn it on, then restore again to bring them back.',
          'Settings for 1 person were left out because Record receiver details is off. Turn it on, then restore again to bring them back.',
          'Settings for 2 people were left out because Record receiver details is off. Turn it on, then restore again to bring them back.',
        ]
      ),
      'hardPaymentsCount': (hardPaymentsCount, ['0 payments', '1 payment', '2 payments']),
    };
    for (final e in counted.entries) {
      test(e.key, () {
        for (var n = 0; n <= 2; n++) {
          expect(e.value.$1(n), e.value.$2[n], reason: 'n = $n');
        }
      });
    }
    test('no counted line ever says "1 people"', () {
      for (final e in counted.values) {
        expect(e.$1(1), isNot(contains('1 people')));
      }
    });
  });

  test('no value in the file says "ceiling"', () {
    final values = <String>[
      kHardLevelSuggested, kHardLevelAskFirst, kHardLevelAutoRecord,
      for (final l in RuleLevel.values) hardRuleLevelName(l),
      for (final l in RuleLevel.values) hardGroupName(l),
      hardSheetTitle('Bob'), hardSheetNoteSuggested('Bob'), hardSheetNoteAskFirst('Rent'), kHardSheetNoteAutoRecord,
      kHardCeilingLabel, kHardCeilingPrefix, kHardCeilingPlaceholder, kHardCeilingHint, kHardCeilingError,
      kTodoHardCeilingTooHigh,
      kHardWhyNotPaybill, kHardPaybillAlwaysAsks, kHardWhyNotWithdrawal,
      hardConfirmTitle('Bob'), hardConfirmBodyNoCeiling('Bob', 'Rent'), hardConfirmBodyCeiling('Bob', 'Rent', 150000),
      kHardConfirmTurnOn,
      hardOfferTitle('Bob'), hardOfferBody('Bob', 'Rent', 3), kHardOfferNotNow, kHardOfferAskFirst, kHardOfferAutoRecord,
      for (final l in RuleLevel.values) hardPillStage1('Bob', l),
      hardPillStage2('Bob', null), hardPillStage2('Bob', 150000), kHardPillStage2Sub, kHardPillChangeCeiling,
      hardPillSuggested('Bob'), hardPillAskFirst('Bob', 'Rent'), hardPillAuto('Bob', 'Rent'), kHardPillAnyAmount,
      kHardPillSetLimit, hardPillUpTo(150000), kHardPillChange,
      hardAutoArrived('Bob', 45000, 'Rent'), hardUndoStays('Bob'),
      kHardPauseTitle, kHardPauseSub, hardPausedBanner(2), kHardResume, kHardPausedToast, hardResumedToast(2),
      kHardPausedTag, kHardPauseSettingsTitle, kHardPauseSettingsSub, kHardPausedNoticeTitle,
      kHardResetButton, hardResetTitle(2), kHardResetBody, kHardResetOk, hardResetToast(2),
      kHardForgetButton, hardForgetTitle(2), kHardForgetBody, kHardForgetOk, hardForgetToast(2),
      kHardPageHelper, hardGroupShow(2), kHardGroupHide, kHardSearchPlaceholder, kHardSearchEmpty,
      kHardRowAutoNoCeiling, hardRowAutoCeiling(150000), kHardRowPaused, kHardRowAskFirstHighest,
      kHardSuggestsFromLast10, kHardDetailsOffLine, kHardDetailsOffCard, kHardTurnOnInSettings, kHardOpenSettings,
      kHardDetailsOffEmpty, kHardSetUpButton, kHardSetUpTitle, kHardRecentlyRecorded, kHardAutoRecordTag,
      kHardSuggestFrom, kHardSuggestLast10, kHardSuggestChoose, kHardSuggestHowTitle, hardSuggestHowLast10('Bob'),
      hardSuggestHowChosen('Bob', 2), kHardSuggestAlertPreview, kHardSuggestNoneChosen, kHardSuggestNeedOne,
      kHardAskHowTitle, hardAskHow('Bob', 'Rent'), kHardAutoHowTitle, hardAutoHow('Bob', 'Rent'),
      kHardLimitHelpTitle, kHardLimitHelp, kHardLimitNotSet, kHardLimitEmptyHint, hardPaymentsCount(2), kHardSetTo,
      kHardLevelSuggestButton, kHardBack, kHardSuggestCurrentLabel, kHardSuggestChooseButton,
      hardSuggestChangeButton(1, 2), hardSuggestKeeps('Bob', 'Auto-record'), kHardCategoryLabel, kHardCategoryChoose,
      kHardCategoryMostUsed, hardCategoryWaiting('Bob'), kHardCategoryNeed, kHardCategoryError, kHardNoCategoryYet,
      kHardSave,
      hardPickerTitleMulti('Bob'), hardPickerTitleOne('Bob'), hardPickerUpTo(2), hardPickerCount(1, 2),
      kHardPickerUsedBefore, hardPickerLimit(2), kHardPickerDone,
      kHardTypeChipsGroup, kHardTypeChipAll, for (final c in kHardTypeChips) ...[c.$1, c.$2], kHardSetUpSearch,
      kHardSetUpHint, kHardSheetTaller, kHardSheetShorter, hardSetUpAccount('1234***'), kHardAirtimeMyself,
      kHardAirtimeOther, hardRowSuggests('Rent, Transport'), hardRowAsks('Rent'), hardRowRecordsUpTo('Rent', 150000),
      hardRowRecordsNoLimit('Rent'), kHardGroupNone, kHardPageFirstTime,
      hardReviewLine(2), kHardReviewButton, kHardReviewTitle, kHardReviewSub, kHardReviewConfirm, kHardReviewKeepAll,
      hardReviewToast(2), kHardReviewKeptToast, hardRestoreToast(2), kHardRestoreOffTitle, hardRestoreOffBody(2),
      kTodoAutoRecordArrivedToast,
    ];
    for (final v in values) {
      expect(v.toLowerCase(), isNot(contains('ceiling')), reason: v);
    }
  });

  test('type chips: the mock-remembered-v2 codes and names, names from sourceTypeName', () {
    expect(kHardTypeChips, [
      ('SM', 'Send Money'),
      ('PB', 'Paybill'),
      ('BG', 'Buy Goods'),
      ('P', 'Pochi'),
      ('A', 'Airtime'),
    ]);
  });

  test('the open PM items stay out: "Turn on" is unchanged', () {
    expect(kHardConfirmTurnOn, 'Turn on');
  });

  test('pill lines never carry a phone number (only the name and category given)', () {
    for (final s in [hardPillSuggested('Bob'), hardPillAskFirst('Bob', 'Rent'), hardPillAuto('Bob', 'Rent'), hardUndoStays('Bob')]) {
      expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
    }
  });
}
