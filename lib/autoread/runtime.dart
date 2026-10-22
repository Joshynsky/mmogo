/// §AUTOREAD.RUNTIME — the ONE bridge, the ONE pending-items store and the ONE
/// reading controller of the process, shared by main.dart, the Settings rows
/// and Delete data (a second bridge would replace the channel's pushed-call
/// handler). Static and lazy: the standard build never touches it.
///
/// [install] runs in `main()` BEFORE the start-up reset resume, so a Delete data
/// that was cut short is finished with the auto-read wipe too.
library;

import '../data/maintenance/reset_resume.dart' show ResetEnv;

import 'bridge/method_channel_autoread_bridge.dart';
import 'data/autoread_wipe.dart';
import 'data/pending_items_store.dart';
import 'logic/reading_controller.dart';

class AutoReadRuntime {
  AutoReadRuntime._();

  /// The per-item store. The bridge's generation is the store's, so Off and
  /// Delete data (which bump it) make an older parse stale.
  static final SharedPrefsPendingItemsStore store = SharedPrefsPendingItemsStore();

  static final MethodChannelAutoReadBridge bridge =
      MethodChannelAutoReadBridge(generation: () => store.readGeneration());


  /// Set by the running app: rebuilds the waiting rows after Delete data.
  static Future<void> Function()? refresh;

  /// Launch and resume: the switch is forced off when consent is not current
  /// (see `ReadingController.reconcile`). Never throws.
  static Future<void> reconcile() async {
    try {
      await ReadingControllerHolder.instance?.reconcile();
    } catch (_) {}
  }

  /// Sets the controller and the Delete data hook. Safe to call twice.
  static void install() {
    ReadingControllerHolder.instance ??= ReadingController(
      bridge: ChannelReadingBridge(bridge),
      store: store,
      prefs: SharedReadingPrefs(),
    );
    ResetEnv.defaultDeviceWipe = AutoReadWipe(refresh: () async => refresh?.call()).run;
  }
}
