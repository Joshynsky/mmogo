/// §AUTOREAD.HELD_ROW_DESCRIBER - asks for a held row's description once when
/// the row appears and hands it to [builder]. The description lives only in
/// this widget's state: it is hidden at once when the app starts to leave the
/// screen, dropped when the app is paused, hidden or detached, and when the last such row leaves the screen ([clear] is called
/// then so the repository forgets too). A failed look is null.
library;

import 'package:flutter/widgets.dart';

import '../model/held_description.dart';
import '../model/waiting_item.dart';

class HeldRowDescriber extends StatefulWidget {
  const HeldRowDescriber({
    super.key,
    required this.item,
    required this.describe,
    required this.builder,
    this.clear,
  });

  final WaitingItem item;
  final Future<HeldDescription?> Function(WaitingItem item) describe;
  final void Function()? clear;
  final Widget Function(BuildContext context, HeldDescription? description) builder;

  @override
  State<HeldRowDescriber> createState() => _HeldRowDescriberState();
}

class _HeldRowDescriberState extends State<HeldRowDescriber> with WidgetsBindingObserver {
  /// Rows of this kind on screen now; at zero the page has been left.
  static int _alive = 0;

  HeldDescription? _description;
  int _token = 0;
  bool _hidden = false;

  /// True from the first step of leaving the app (frames still paint then, so
  /// the screenshot the phone keeps shows the plain title, not the description).
  bool _masked = false;

  bool get _describable =>
      widget.item.kind == WaitingKind.readyToParse || widget.item.kind == WaitingKind.unreadable;

  @override
  void initState() {
    super.initState();
    _alive++;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(HeldRowDescriber old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.item.kind != widget.item.kind) {
      _description = null;
      _load();
    }
  }

  void _load() {
    final token = ++_token;
    if (!_describable || _hidden) return;
    widget.describe(widget.item).then<void>((d) {
      if (mounted && token == _token && !_hidden) setState(() => _description = d);
    }, onError: (Object _) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        setState(() => _masked = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _hidden = true;
        _masked = true;
        _token++;
        _description = null;
        widget.clear?.call();
      case AppLifecycleState.resumed:
        _masked = false;
        if (_hidden) {
          _hidden = false;
          _load();
        }
        setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _token++;
    _alive--;
    if (_alive == 0) widget.clear?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _masked ? null : _description);
}
