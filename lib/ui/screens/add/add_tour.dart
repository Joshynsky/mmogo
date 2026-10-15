import 'package:flutter/material.dart';

import '../../shell/primary_shell.dart';
import '../../shell/routes.dart';
import '../../widgets/coach_tour.dart';

/// §ADD.TOUR — Add's coach tour: the page id, the step list and the "Take me
/// there" jump. Moved out of `add_screen.dart` (0.1.2 S8c-1 step 0), unchanged.
///
/// Add's coach-tour page id (the seen flag is `tour_seen_add`).
const addTourId = 'add';

/// Sends the user to the Paid to tab (Add is pushed over the shell).
void goToPaidToFromAdd(BuildContext context) {
  final shell = PrimaryShell.active;
  if (shell != null) {
    Navigator.of(context).popUntil((route) => route == shell.route);
    shell.select(3);
  } else {
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.paidTo, (route) => false);
  }
}

/// The tour for the current tab (the Cash tab gets a shorter list).
List<CoachStep> addTourSteps({
  required bool cash,
  required GlobalKey pasteKey,
  required GlobalKey segKey,
  required GlobalKey receiverKey,
  required GlobalKey categoryKey,
  required VoidCallback onGoToPaidTo,
  bool hasReceiver = true, // Airtime has no receiver card
}) {
  final categoryStep = CoachStep(
    target: categoryKey,
    text: 'Pick a category. Tick Always use to remember it for this receiver.',
    onEnter: () => scrollIntoView(categoryKey),
  );
  if (cash) {
    return [
      CoachStep(target: segKey, text: 'Switch back to M-Pesa to paste a message.'),
      categoryStep,
    ];
  }
  return [
    CoachStep(
      target: pasteKey,
      text: 'Paste an M-Pesa message and we fill the form in. You check it before saving.',
    ),
    CoachStep(target: segKey, text: 'Paid in cash? Switch to Cash.'),
    if (hasReceiver)
      CoachStep(
        target: receiverKey,
        text: 'Record the receiver’s name and phone to see this person on Paid to.',
        actionLabel: 'Take me there',
        onAction: onGoToPaidTo,
        onEnter: () => scrollIntoView(receiverKey),
      ),
    categoryStep,
  ];
}
