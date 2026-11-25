import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// §SHELL.BACK_KEYBOARD (0.2.2, F6): Android Back with the keyboard open closes
/// the keyboard only; the next Back goes on as usual (closes the sheet or page).
///
/// One observer for the whole app, so no sheet needs its own handling. It is
/// installed BEFORE `runApp`, so it is asked before the Navigator's own observer
/// (observers are asked in the order they were added and the first `true` wins).
class BackClosesKeyboard with WidgetsBindingObserver {
  BackClosesKeyboard._();

  static BackClosesKeyboard? _installed;

  /// Adds the observer once; later calls do nothing. Needs the binding.
  static void install() {
    if (_installed != null) return;
    _installed = BackClosesKeyboard._();
    WidgetsBinding.instance.addObserver(_installed!);
  }

  /// Removes it (tests only).
  static void uninstallForTest() {
    final o = _installed;
    if (o == null) return;
    WidgetsBinding.instance.removeObserver(o);
    _installed = null;
  }

  /// True when the on-screen keyboard is showing: any view has a bottom inset.
  static bool keyboardOpen(Iterable<FlutterView> views) => views.any((v) => v.viewInsets.bottom > 0);

  @override
  Future<bool> didPopRoute() async {
    if (!keyboardOpen(WidgetsBinding.instance.platformDispatcher.views)) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    return true; // used up: the sheet or page stays
  }
}
