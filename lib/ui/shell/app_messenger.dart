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
