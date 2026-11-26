/// §AUTOREAD.LEVELS.SETUP_OPEN: the bottom bar's "Set up" action (0.2.2 item 2 redesign, I2): opens the Set up
/// sheet (setup_sheet.dart) over the Remembered page's second tab with the app's Set up list
/// ([LevelsDeps.setup]). A row opens that person's sheet (openLevelSheetFor, with the chips picker and the row's
/// "{k} payments"); the Set up sheet waits for it, reads its list again and puts the focus back on the row. The
/// Airtime chip (PM Q3: only a way to the existing Airtime switches in 0.2.2) closes the sheet and scrolls the
/// tab to its Airtime switches. No Set up list = no action (the bar hides its button).
library;

import 'package:flutter/widgets.dart';

import 'level_sheet_open.dart';
import 'levels_deps.dart';
import 'setup_sheet.dart';

/// The key of the tab's Airtime heading (levels_tab.dart), the place the Airtime chip leads to.
const Key kLevelsAirtimeHeaderKey = Key('levelsAirtimeHeader');

/// The Set up action for [d] (null when there is no Set up list). [context] is the tab's.
Future<void> Function(BuildContext context)? setUpActionFor(LevelsDeps d) {
  final source = d.setup;
  if (source == null) return null;
  return (context) => showSetupSheet(
        context,
        source: source,
        onPick: (r) => openLevelSheetFor(context, d, r.type, r.key, r.displayName, paymentCount: r.paymentCount),
        onAirtime: () => scrollToAirtimeSwitches(context),
      );
}

/// Brings the tab's Airtime switches into view (under [context]); nothing when the tab's list is not there.
/// The list builds lazily, so a heading far below is not built yet: the list then goes to its end first (the
/// Airtime switches are its last part), and the heading is aligned to the top once it is built.
void scrollToAirtimeSwitches(BuildContext context) {
  if (!context.mounted) return;
  final header = _find(context, (e) => e.widget.key == kLevelsAirtimeHeaderKey);
  if (header != null) {
    _reveal(header);
    return;
  }
  final list = _find(context, (e) => e.widget.key == kLevelsTabListKey);
  final scrollable = list == null ? null : _find(list, (e) => e is StatefulElement && e.state is ScrollableState);
  if (scrollable == null) return;
  final position = ((scrollable as StatefulElement).state as ScrollableState).position;
  position.jumpTo(position.maxScrollExtent);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final built = _find(context, (e) => e.widget.key == kLevelsAirtimeHeaderKey);
    if (built != null) _reveal(built);
  });
}

/// The tab's scrolling list (levels_tab.dart).
const Key kLevelsTabListKey = Key('levelsTab');

void _reveal(Element e) =>
    Scrollable.ensureVisible(e, alignment: 0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

/// The first element under [root] (not [root] itself) that [test] accepts, depth first.
Element? _find(BuildContext root, bool Function(Element e) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  root.visitChildElements(visit);
  return found;
}
