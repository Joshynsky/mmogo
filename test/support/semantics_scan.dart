// S11b (CB5): small helpers to read the semantics tree in widget tests.
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every node of the tree (children as the framework lists them: reading order).
List<SemanticsNode> semanticsNodes(WidgetTester t) {
  // The root owner has no tree in the widget-test binding; the test binding's owner does.
  // ignore: deprecated_member_use
  final root = t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(root);
  return out;
}

/// Nodes the user can activate (tap) that have no label, value, hint or tooltip
/// (a Flutter tooltip is what names an icon button for a screen reader): a
/// screen reader would say nothing for them.
List<String> unlabelledTappables(WidgetTester t) => [
  for (final n in semanticsNodes(t))
    if (n.getSemanticsData().hasAction(SemanticsAction.tap) &&
        !n.flagsCollection.isHidden &&
        n.label.trim().isEmpty &&
        n.value.trim().isEmpty &&
        n.hint.trim().isEmpty &&
        n.tooltip.trim().isEmpty)
      'node ${n.id} rect ${n.rect}',
];

/// F2 (R51, R53): nodes that carry a switch / tick state but have no label of
/// their own (a screen reader says "on" or "checked" with no name). A row whose
/// switch or tick is merged into the row's label has none of these.
List<String> unnamedStateNodes(WidgetTester t) => [
  for (final n in semanticsNodes(t))
    if (!n.flagsCollection.isHidden &&
        (n.flagsCollection.isToggled != Tristate.none || n.flagsCollection.isChecked != CheckedState.none) &&
        n.label.trim().isEmpty)
      'node ${n.id} rect ${n.rect}',
];

/// The labels of heading nodes, in tree (reading) order.
List<String> headingLabels(WidgetTester t) => [
  for (final n in semanticsNodes(t))
    if (n.flagsCollection.isHeader && !n.flagsCollection.isHidden) n.label.trim(),
];

/// Headings found while paging down a lazy list: the first view, then after each
/// scroll of [step] pixels, in order, without repeats.
Future<List<String>> headingsWhileScrolling(WidgetTester t, Finder scrollView, {double step = 250, int maxSteps = 30}) async {
  final seen = <String>[];
  void add() {
    for (final h in headingLabels(t)) {
      if (!seen.contains(h)) seen.add(h);
    }
  }

  add();
  for (var i = 0; i < maxSteps; i++) {
    await t.drag(scrollView, Offset(0, -step));
    await t.pump(const Duration(milliseconds: 300));
    add();
  }
  return seen;
}
