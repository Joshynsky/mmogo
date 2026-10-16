// S11b TS2 (text-size 1.3 matrix): one subject = one testWidgets that builds the
// screen or sheet at 360 x 640 in three variants, one after the other:
//   control (1.0, light), 1.3 light, 1.3 dark   (B6: control stays light only)
// and asserts, per variant:
//   - no exception (overflow shows up as a FlutterError) at any point,
//   - every action is found (scrolling to it when the layout scrolls), on
//     screen, hit-testable at its centre, and at least 44 x 44 unless the
//     subject lists it in [known] (a logged item, never a silent skip),
//   - no two actions on screen overlap.
// Everything is a fake: build the subject from fakes and stub routes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/tap_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One action button of a subject.
class A11yAction {
  const A11yAction(this.name, this.finder, {this.knownSmall, this.floating = false});

  final String name;
  final Finder finder;

  /// Why this one is allowed under 44 px (a logged LOG-ITEM), or null.
  final String? knownSmall;

  /// A control that floats over scrolling content by design (the Add button):
  /// still reached and hit-tested, never counted in the overlap check.
  final bool floating;
}

class A11yVariant {
  const A11yVariant(this.name, this.scale, this.dark);
  final String name;
  final double scale;
  final bool dark;
}

const kA11yVariants = <A11yVariant>[
  A11yVariant('control 1.0 light', 1.0, false),
  A11yVariant('1.3 light', 1.3, false),
  A11yVariant('1.3 dark', 1.3, true),
];

const kA11ySize = Size(360, 640);

/// Findings that are logged, not failures (known small targets); printed so
/// the deviations file can quote them.
final List<String> a11yLog = <String>[];

Future<void> a11ySettle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

/// Pumps [home] under the palette scope, with text scale and a 360 x 640 view.
Future<void> pumpA11y(
  WidgetTester t,
  Widget home, {
  required A11yVariant variant,
  Map<String, WidgetBuilder> routes = const {},
  Object? routeArgs,
  Size size = kA11ySize,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', variant.dark ? 'dark' : 'light'),
      child: MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(variant.scale)),
          child: child!,
        ),
        routes: routeArgs == null ? routes : const {},
        home: routeArgs == null ? home : null,
        onGenerateRoute: (s) => routeArgs != null && s.name == '/'
            ? MaterialPageRoute(settings: RouteSettings(name: s.name, arguments: routeArgs), builder: (_) => home)
            : MaterialPageRoute(settings: s, builder: (_) => const Scaffold(body: Text('STUB'))),
      ),
    ),
  );
  await a11ySettle(t);
}

/// Drains pending framework exceptions (an overflow is one) into [problems].
void drainExceptions(WidgetTester t, String where, List<String> problems) {
  for (var i = 0; i < 20; i++) {
    final e = t.takeException();
    if (e == null) return;
    final line = e.toString().split('\n').first;
    problems.add('EXCEPTION $where: $line');
  }
}

Future<bool> _reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    // A lazy list has not built it yet: scroll each vertical scroll view in turn.
    final all = find.byType(Scrollable);
    for (var i = 0; i < all.evaluate().length && f.evaluate().isEmpty; i++) {
      final state = t.state<ScrollableState>(all.at(i));
      if (state.axisDirection != AxisDirection.down && state.axisDirection != AxisDirection.up) continue;
      for (final delta in const [160.0, -160.0]) {
        if (f.evaluate().isNotEmpty) break;
        try {
          await t.scrollUntilVisible(f, delta, scrollable: all.at(i), maxScrolls: 80);
        } catch (_) {
          // not in this direction
        }
        t.takeException();
      }
    }
  }
  if (f.evaluate().isEmpty) return false;
  // Already reachable (centre on screen and hit-testable): do not move it (ensureVisible
  // would align it to the leading edge and a snapping strip would then move it again).
  final c = t.getRect(f.first).center;
  if (!(Offset.zero & kA11ySize).contains(c) || f.first.hitTestable().evaluate().isEmpty) {
    await t.ensureVisible(f.first);
  }
  await a11ySettle(t);
  return true;
}

Rect _rect(WidgetTester t, Finder f) => t.getRect(f.first);

String _r(Rect r) => '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}@(${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)})';

/// Where each action sits right now, as the part the user can see: clipped to
/// the viewport of the scroll view it lives in (content scrolled under a pinned
/// bar is not counted). Only actions whose visible part contains their centre.
Map<String, Rect> snapshotRects(WidgetTester t, List<A11yAction> actions, {Set<String> skip = const {}}) {
  final view = Offset.zero & kA11ySize;
  final out = <String, Rect>{};
  for (final a in actions) {
    if (a.floating || skip.contains(a.name) || a.finder.evaluate().isEmpty) continue;
    var r = _rect(t, a.finder);
    final scrollable = Scrollable.maybeOf(t.element(a.finder.first));
    final box = scrollable?.context.findRenderObject();
    if (box is RenderBox) r = r.intersect(box.localToGlobal(Offset.zero) & box.size);
    if (r.width > 0 && r.height > 0 && view.contains(r.center)) out[a.name] = r;
  }
  return out;
}

/// Pairs of [rects] that overlap (more than 1 px each way). Judged where the
/// layout starts, before any scrolling: content scrolled under a pinned bar is
/// not an overlap.
List<String> overlapProblems(Map<String, Rect> rects, String label) {
  final out = <String>[];
  final names = rects.keys.toList()..sort();
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final x = rects[names[i]]!.intersect(rects[names[j]]!);
      if (x.width > 1 && x.height > 1) {
        out.add('$label: "${names[i]}" ${_r(rects[names[i]]!)} overlaps "${names[j]}" ${_r(rects[names[j]]!)}');
      }
    }
  }
  return out;
}

/// The reach checks for [actions]: found (scrolling to it), on screen, hit-testable, >= 44.
Future<List<String>> checkActions(WidgetTester t, List<A11yAction> actions, {required String label}) async {
  final problems = <String>[];
  final view = Offset.zero & kA11ySize;
  for (final a in actions) {
    final found = await _reveal(t, a.finder);
    if (!found) {
      problems.add('$label: action "${a.name}" not found');
      continue;
    }
    drainExceptions(t, 'while revealing "${a.name}" ($label)', problems);
    final r = _rect(t, a.finder);
    if (!view.inflate(0.5).contains(r.center)) problems.add('$label: "${a.name}" centre ${_r(r)} is off screen');
    if (!a.finder.first.hitTestable().evaluate().isNotEmpty) problems.add('$label: "${a.name}" is not hit-testable at ${_r(r)}');
    if (r.width < 43.5 || r.height < 43.5) {
      if (a.knownSmall != null) {
        a11yLog.add('SMALL ${a.name} ${_r(r)} ($label): ${a.knownSmall}');
      } else {
        problems.add('$label: "${a.name}" hit area ${_r(r)} is under 44');
      }
    }
  }
  return problems.toSet().toList();
}

/// Registers one subject. [home] builds the subject fresh for each variant;
/// [open] (optional) opens a sheet or moves to a state after the first frame;
/// [actions] lists the action buttons (called after [open], so finders may be
/// built against the opened state). [prefs] seeds mock SharedPreferences.
void a11ySubject(
  String name, {
  required Widget Function() home,
  required List<A11yAction> Function() actions,
  Future<void> Function(WidgetTester t)? open,
  Map<String, WidgetBuilder> routes = const {},
  Object? routeArgs,
  Map<String, Object> prefs = const {},
  Size size = kA11ySize,
  Future<void> Function()? before,
  List<A11yVariant> variants = kA11yVariants,
}) {
  testWidgets('TS2 matrix: $name', (t) async {
    addTearDown(t.view.reset);
    final problems = <String>[];
    for (final v in variants) {
      SharedPreferences.setMockInitialValues({...prefs});
      if (before != null) await before();
      await pumpA11y(t, home(), variant: v, routes: routes, routeArgs: routeArgs, size: size);
      drainExceptions(t, 'build ($name, ${v.name})', problems);
      final label = '$name, ${v.name}';
      var pre = <String, Rect>{};
      if (open != null) {
        pre = snapshotRects(t, actions());
        problems.addAll(overlapProblems(pre, label));
        await open(t);
        await a11ySettle(t);
        drainExceptions(t, 'open ($name, ${v.name})', problems);
      }
      final acts = actions();
      problems.addAll(overlapProblems(snapshotRects(t, acts, skip: pre.keys.toSet()), label));
      problems.addAll(await checkActions(t, acts, label: label));
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }
    for (final p in problems) {
      // ignore: avoid_print
      print('A11Y: $p');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

/// The tap box (TapTarget) around a small visual: that box is the hit area.
Finder viaTapTarget(Finder visual) => find.ancestor(of: visual, matching: find.byType(TapTarget));

/// For `tearDownAll`: prints the logged (allowed, known-small) findings so the
/// deviations file can quote them.
void printA11yLog() {
  for (final line in a11yLog) {
    // ignore: avoid_print
    print(line);
  }
}
