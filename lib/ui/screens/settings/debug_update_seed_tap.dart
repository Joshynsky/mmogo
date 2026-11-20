import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../widgets/pill_toast.dart';
import '../../../data/updates/debug_release_seed.dart';
import '../../../data/updates/updates_inbox.dart';

/// 0.2.1 #3 — DEBUG ONLY. A long press on its [child] (the Settings footer line) seeds a release
/// notice one patch newer than the installed version, so the News "Update" row can be checked on a
/// phone. In a release build ([kDebugMode] false) it is just [child]: no gesture, no seed call.
class DebugUpdateSeedTap extends StatelessWidget {
  const DebugUpdateSeedTap({super.key, required this.child, this.inbox});

  final Widget child;
  final UpdatesInbox? inbox;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return GestureDetector(
      key: const Key('debugUpdateSeed'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        final tag = await seedNewerReleaseNotice(inbox ?? UpdatesInbox.instance);
        // WORDING-DRAFT (debug only, never in a release build)
        PillToast.show(tag == null ? 'Debug: update notice not added' : 'Debug: update notice $tag added');
      },
      child: child,
    );
  }
}
