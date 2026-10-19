/// §AUTOREAD.T1 — the T1 test host: a plain, throwaway test screen for the
/// first installable autoread build (debug + MMOGO_AUTOREAD only). Removed
/// when the real Notifications page (FE-N1) lands. It never reads or shows a
/// message body: there is no peekHeld here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../bridge/method_channel_autoread_bridge.dart';
import 't1_test_copy.dart';

/// The host exists only in a debug build compiled with the autoread define.
bool t1HostEnabled(bool compiled, bool debug) => compiled && debug;

/// What the test screen needs. No body access by design.
abstract class T1Controls {
  Future<AutoReadState> getState();
  Future<bool> setEnabled(bool enabled);
  Future<AutoReadPermissions> requestPermissions();
  Future<String?> takeLaunchId();
  Stream<String> get tapped;
  Future<List<String>> listHeldIds();
  Future<void> deleteAllHeld();
  Future<void> openAppSettings();
}

/// The app's adapter over the real bridge.
class BridgeT1Controls implements T1Controls {
  final MethodChannelAutoReadBridge _bridge;
  BridgeT1Controls(this._bridge);

  @override
  Future<AutoReadState> getState() => _bridge.getState();
  @override
  Future<bool> setEnabled(bool enabled) => _bridge.setEnabled(enabled);
  @override
  Future<AutoReadPermissions> requestPermissions() => _bridge.requestPermissions();
  @override
  Future<String?> takeLaunchId() => _bridge.takeLaunchId();
  @override
  Stream<String> get tapped => _bridge.tapped;
  @override
  Future<List<String>> listHeldIds() => _bridge.listHeldIds();
  @override
  Future<void> deleteAllHeld() => _bridge.deleteAllHeld();
  @override
  Future<void> openAppSettings() => _bridge.openAppSettings();
}

class T1TestHost extends StatefulWidget {
  const T1TestHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.controls,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Null = the real bridge adapter.
  final T1Controls? controls;

  @override
  State<T1TestHost> createState() => _T1TestHostState();
}

class _T1TestHostState extends State<T1TestHost> {
  late final T1Controls _controls = widget.controls ??
      BridgeT1Controls(MethodChannelAutoReadBridge(generation: () async => 0));
  final ValueNotifier<String?> _lastTap = ValueNotifier<String?>(null);
  final Set<String> _seen = <String>{};
  StreamSubscription<String>? _sub;
  bool _screenOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = _controls.tapped.listen(_onTap);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final id = await _controls.takeLaunchId();
        if (id != null && mounted) _onTap(id);
      } catch (_) {
        // The test screen shows errors on its own controls; a failed launch
        // read is simply "no tap".
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lastTap.dispose();
    super.dispose();
  }

  void _onTap(String id) {
    if (!_seen.add(id)) return; // once per id
    _lastTap.value = id;
    _openScreen();
  }

  void _openScreen() {
    if (_screenOpen) return;
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    _screenOpen = true;
    nav
        .push<void>(MaterialPageRoute<void>(
          builder: (_) => T1TestScreen(controls: _controls, lastTap: _lastTap),
        ))
        .whenComplete(() => _screenOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        PositionedDirectional(
          top: 0,
          end: 0,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: kT1CornerSemantics,
              excludeSemantics: true,
              child: Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openScreen,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Text(
                        kT1CornerLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class T1TestScreen extends StatefulWidget {
  const T1TestScreen({super.key, required this.controls, required this.lastTap});

  final T1Controls controls;
  final ValueListenable<String?> lastTap;

  @override
  State<T1TestScreen> createState() => _T1TestScreenState();
}

class _T1TestScreenState extends State<T1TestScreen> with WidgetsBindingObserver {
  AutoReadState? _state;
  bool? _tapHeld;
  String? _errorCode;
  bool _smsStillOff = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lastTap.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.lastTap.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  String _codeOf(Object e) => e is AutoReadBridgeException ? e.code : 'failed';

  /// Runs one control action; an error becomes the plain code line.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
      if (mounted) setState(() => _errorCode = null);
    } catch (e) {
      if (mounted) setState(() => _errorCode = _codeOf(e));
    } finally {
      _busy = false;
    }
    if (mounted) await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.controls.getState();
      bool? held;
      final tap = widget.lastTap.value;
      if (tap != null) {
        held = (await widget.controls.listHeldIds()).contains(tap);
      }
      if (!mounted) return;
      setState(() {
        _state = s;
        _tapHeld = held;
      });
    } catch (e) {
      if (mounted) setState(() => _errorCode = _codeOf(e));
    }
  }

  Future<void> _toggle(bool on) => _run(() async {
        _smsStillOff = false;
        if (!on) {
          await widget.controls.setEnabled(false);
          return;
        }
        if (!(_state?.smsGranted ?? false)) {
          final p = await widget.controls.requestPermissions();
          if (!p.smsGranted) {
            _smsStillOff = true;
            return;
          }
        }
        await widget.controls.setEnabled(true);
      });

  Widget _btn(String label, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: onPressed,
            child: Text(label),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final tap = widget.lastTap.value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(kT1Title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(kT1Intro),
            const SizedBox(height: 16),
            if (s != null) ...[
              Text(s.enabled ? kT1ReadOn : kT1ReadOff),
              Text(s.smsGranted ? kT1SmsAllowed : kT1SmsNotAllowed),
              Text(s.notifGranted ? kT1NotifAllowed : kT1NotifNotAllowed),
              Text(t1Waiting(s.heldCount)),
            ],
            const SizedBox(height: 8),
            _btn(kT1AllowPermissions,
                () => _run(() async => widget.controls.requestPermissions())),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(kT1SwitchLabel),
                value: s?.enabled ?? false,
                onChanged: _toggle,
              ),
            ),
            if (_smsStillOff) const Text(kT1SmsStillOff),
            _btn(kT1OpenSettings, () => _run(widget.controls.openAppSettings)),
            _btn(kT1DeleteHeld, () => _run(widget.controls.deleteAllHeld)),
            _btn(kT1Refresh, _refresh),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t1Error(_errorCode!),
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Text(kT1TapHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(tap == null
                ? kT1NoTap
                : t1TapLine(
                    tap.length > 6 ? tap.substring(tap.length - 6) : tap,
                    _tapHeld ?? false)),
          ],
        ),
      ),
    );
  }
}
