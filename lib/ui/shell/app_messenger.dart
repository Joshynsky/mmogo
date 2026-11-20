import 'package:flutter/material.dart';

/// T27 — a stable, app-wide [ScaffoldMessengerState] handle.
///
/// Add's "Check before saving" review sheet saves, then pops the whole Add
/// screen back to whatever page opened it (returning to the shell with a
/// "Saved" confirmation). By the time that confirmation should show, Add's
/// own `Scaffold`/`ScaffoldMessenger` has already been popped away with it —
/// `ScaffoldMessenger.of(context)` from Add's context would resolve to a
/// messenger that's mid-disposal. Routing the SnackBar through this one
/// root-level key (attached to `MaterialApp.scaffoldMessengerKey` in
/// `main.dart`) shows it on whichever page is now on screen instead,
/// regardless of which page that is.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 0.2.1 beta: the root navigator's key, so a toast can reach the root overlay from anywhere (no context
/// needed). The app root (`MpesaTrackerApp`) makes a fresh key per instance and publishes it here, so a soft
/// restart never reuses the old Navigator (and its routes) through a shared GlobalKey. `PillToast` inserts
/// into this navigator's overlay; a test that needs the toast puts `navigatorKey: appNavigatorKey` on its app.
GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
