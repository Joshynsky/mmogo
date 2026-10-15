import 'dart:io';

/// §DATA.MAINTENANCE.FS — the file-system seam of Reset app (step 4). A test
/// passes a fake that refuses a delete ("locked file"); the real one is `dart:io`.
abstract class DataFileSystem {
  Future<bool> exists(String path);

  /// Deletes the file. Throws when it cannot (a missing file is not an error).
  Future<void> delete(String path);
}

class IoDataFileSystem implements DataFileSystem {
  const IoDataFileSystem();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
