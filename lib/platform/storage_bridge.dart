import 'dart:typed_data';

import 'method_channel_storage_bridge.dart';

/// Why a storage call failed. Mirrors the codes the Kotlin side sends.
enum StorageErrorCode {
  /// The user backed out of a picker.
  cancelled,

  /// The picked file is larger than the allowed size.
  tooLarge,

  /// The folder permission was revoked or never held.
  grantLost,

  /// Anything else: disk, provider, bad arguments, a second picker, unknown.
  io;

  /// Wire name, as sent by Kotlin. Unknown names map to [io].
  static StorageErrorCode fromWire(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return io;
  }
}

class StorageException implements Exception {
  const StorageException(this.code, [this.message]);

  final StorageErrorCode code;
  final String? message;

  @override
  String toString() => 'StorageException(${code.name}${message == null ? '' : ': $message'})';
}

class PickedFolder {
  const PickedFolder({required this.uri, required this.name});
  final String uri;
  final String name;
}

class PickedFile {
  const PickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class FolderFile {
  const FolderFile({required this.name, required this.uri, required this.size, required this.lastModified});
  final String name;
  final String uri;
  final int size;
  final DateTime lastModified;
}

/// Folder picker and file access (architecture D4). Methods throw only
/// [StorageException]. Pickers return null when the user cancels.
abstract interface class StorageBridge {
  /// Replaceable in tests (assign a fake).
  static StorageBridge instance = MethodChannelStorageBridge();

  Future<PickedFolder?> pickFolder();

  /// True only when the permission is still held and the folder still resolves.
  Future<bool> hasWriteGrant(String treeUri);

  Future<void> releaseGrant(String treeUri);

  /// Creates a NEW file and returns its URI (authoritative: the name may have
  /// been changed to avoid a clash). Never overwrites.
  Future<String> createFile(String treeUri, String name, Uint8List bytes);

  Future<List<FolderFile>> listFiles(String treeUri);

  Future<void> deleteFile(String docUri);

  /// Throws [StorageErrorCode.tooLarge] when the file exceeds [maxBytes].
  Future<PickedFile?> pickFile({required int maxBytes});

  /// Opens one of the two [AppConstants] URLs; false for anything else or
  /// when nothing can open it.
  Future<bool> openUrl(String url);
}
