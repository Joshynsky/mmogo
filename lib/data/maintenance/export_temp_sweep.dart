import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 0.1.3 SEC-03. A CSV export writes `mmogo-export-<time>.csv` into the app's temp folder and
// the share sheet's plugin keeps a second copy in `share_plus/` beside it. Both hold the user's
// names, numbers and amounts as plain text, so they are removed after the share, before the next
// export (an older version left them behind), and when Delete data finishes.

const String kExportTempPrefix = 'mmogo-export-';

bool _isExportFile(String path) {
  final name = p.basename(path);
  return name.startsWith(kExportTempPrefix) && name.endsWith('.csv');
}

/// Deletes every export file in [cache] and in [cache]/share_plus. Never throws; returns how many
/// files it removed. Other files, and folders, are left alone.
Future<int> sweepExportTemp(Directory cache) async {
  var removed = 0;
  for (final dir in [cache, Directory(p.join(cache.path, 'share_plus'))]) {
    try {
      if (!await dir.exists()) continue;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File || !_isExportFile(e.path)) continue;
        try {
          await e.delete();
          removed++;
        } catch (_) {
          // Nothing more to do: the OS clears its temp folder in time.
        }
      }
    } catch (_) {}
  }
  return removed;
}

/// [sweepExportTemp] on the app's real temp folder; a platform that cannot give one is ignored.
Future<void> sweepExportTempOnDevice() async {
  try {
    await sweepExportTemp(await getTemporaryDirectory());
  } catch (_) {}
}
