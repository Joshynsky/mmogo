// S11b AX1b: where does keyboard / switch focus start on a sheet or dialog, and
// in what order does it travel? The probe reads the real FocusManager, and
// presses Tab (as a keyboard or switch-access user would) to list the stops.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One focus stop: the nearest string key above it (or its type) and where it is.
class FocusStop {
  FocusStop(this.name, this.rect, this.text);
  final String name;
  final Rect rect;

  /// The first text drawn inside the focused control ('' if none).
  final String text;
  @override
  String toString() => '$name[$text]@(${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)})';
}

String _textIn(BuildContext ctx) {
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final w = e.widget;
    if (w is Text) {
      found = w.data ?? w.textSpan?.toPlainText() ?? '';
      return;
    }
    e.visitChildren(visit);
  }

  (ctx as Element).visitChildren(visit);
  return found ?? '';
}

String _nameOf(FocusNode node) {
  final ctx = node.context;
  if (ctx == null) return 'none';
  String? found;
  void check(Element e) {
    final k = e.widget.key;
    if (found == null && k is ValueKey<String>) found = k.value;
  }

  if (ctx is Element) check(ctx);
  ctx.visitAncestorElements((e) {
    check(e);
    return found == null;
  });
  return found ?? ctx.widget.runtimeType.toString();
}

FocusStop? currentStop() {
  final f = FocusManager.instance.primaryFocus;
  if (f == null || f.context == null || !f.hasPrimaryFocus) return null;
  if (f is FocusScopeNode) return null;
  return FocusStop(_nameOf(f), f.rect, _textIn(f.context!));
}

class FocusProbe {
  FocusProbe(this.initial, this.stops);

  /// The control that holds focus the moment the sheet is open (null = no
  /// control: only the route's scope has it).
  final FocusStop? initial;

  /// The Tab stops after that, in order, until the first repeats.
  final List<FocusStop> stops;

  /// The first control the user reaches: the initial focus, else the first Tab stop.
  FocusStop? get first => initial ?? (stops.isEmpty ? null : stops.first);

  @override
  String toString() => 'initial=$initial stops=$stops';
}

/// Reads the initial focus, then presses Tab up to [max] times. Leaves focus
/// wherever it ended.
Future<FocusProbe> probeFocus(WidgetTester t, {int max = 30}) async {
  await t.pump();
  final initial = currentStop();
  final stops = <FocusStop>[];
  for (var i = 0; i < max; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final s = currentStop();
    if (s == null) continue;
    if (stops.any((x) => x.name == s.name && x.rect == s.rect) || (stops.length > 1 && stops.first.name == s.name)) break;
    stops.add(s);
  }
  return FocusProbe(initial, stops);
}

/// True when [stops] read top to bottom, left to right within a row (rows are
/// bands of 12 px), allowing the order to wrap back to the start only at the end.
bool readsTopToBottom(List<FocusStop> stops) {
  for (var i = 1; i < stops.length; i++) {
    final a = stops[i - 1].rect;
    final b = stops[i].rect;
    final sameRow = (a.center.dy - b.center.dy).abs() <= 12;
    final ok = sameRow ? b.left >= a.left - 1 : b.center.dy > a.center.dy;
    if (!ok) return false;
  }
  return true;
}
