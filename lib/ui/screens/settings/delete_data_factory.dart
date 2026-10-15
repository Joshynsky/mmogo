import 'package:flutter/foundation.dart';

import '../../../data/maintenance/delete_data_service.dart';
import '../../shell/primary_shell.dart';

/// §SETTINGS.DELETE_FACTORY — the ONE place the real [DeleteDataServiceImpl]
/// is built for the UI (0.1.2 S9b-2, A1). No widget constructs the Impl; they
/// take a `DeleteDataService?` and fall back to [DeleteDataServices.create].
///
/// A guard test scans `lib/ui` for `DeleteDataServiceImpl(` outside this file,
/// and `test/` for a construction without `env:`.
class DeleteDataServices {
  const DeleteDataServices._();

  /// Tests that reach Settings through the whole app set this to a fake
  /// (`useFakeDeleteData()` in `test/support/fake_delete_data.dart`).
  @visibleForTesting
  static DeleteDataService Function()? override;

  /// The real service: after Level 1 the screens refresh through
  /// `PrimaryShell.active?.dataChanged()` (the service calls it, step f).
  static DeleteDataService create() =>
      (override ?? () => DeleteDataServiceImpl(onDataChanged: () => PrimaryShell.active?.dataChanged()))();
}
