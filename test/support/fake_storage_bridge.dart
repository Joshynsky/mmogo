import 'dart:typed_data';

import 'package:mmogo/app_constants.dart';
import 'package:mmogo/platform/storage_bridge.dart';

/// In-memory [StorageBridge] for tests. One fake folder per tree URI, records
/// every call, can revoke the grant, fail writes, or queue picker answers.
class FakeStorageBridge implements StorageBridge {
  /// Every call as `method` or `method:arg`, in order.
  final List<String> calls = [];

  /// treeUri -> (docUri -> file).
  final Map<String, Map<String, FolderFile>> folders = {};
  final Map<String, Uint8List> contents = {};

  final Set<String> revoked = {};
  final Set<String> released = {};
  final List<String> openedUrls = [];

  /// When true, createFile throws [StorageErrorCode.io] and stores nothing.
  bool failWrites = false;

  /// Answers for the next picker calls (null entry = cancelled). Empty queue
  /// means cancelled.
  final List<PickedFolder?> folderPicks = [];
  final List<PickedFile?> filePicks = [];

  /// When set, the next picker call throws it (then clears).
  StorageException? nextPickError;

  DateTime Function() now = DateTime.now;
  int _seq = 0;

  void revokeGrant(String treeUri) => revoked.add(treeUri);

  /// Seeds a file in a folder and returns its URI.
  String seed(String treeUri, String name, Uint8List bytes, {DateTime? modified}) {
    final uri = '$treeUri/doc/${_seq++}';
    (folders[treeUri] ??= {})[uri] =
        FolderFile(name: name, uri: uri, size: bytes.length, lastModified: modified ?? now());
    contents[uri] = bytes;
    return uri;
  }

  Uint8List? bytesOf(String docUri) => contents[docUri];

  void _need(String treeUri) {
    if (revoked.contains(treeUri) || released.contains(treeUri)) {
      throw const StorageException(StorageErrorCode.grantLost);
    }
  }

  void _pickGuard() {
    final e = nextPickError;
    if (e != null) {
      nextPickError = null;
      throw e;
    }
  }

  @override
  Future<PickedFolder?> pickFolder() async {
    calls.add('pickFolder');
    _pickGuard();
    final pick = folderPicks.isEmpty ? null : folderPicks.removeAt(0);
    if (pick != null) {
      revoked.remove(pick.uri);
      released.remove(pick.uri);
      folders.putIfAbsent(pick.uri, () => {});
    }
    return pick;
  }

  @override
  Future<bool> hasWriteGrant(String treeUri) async {
    calls.add('hasWriteGrant:$treeUri');
    return folders.containsKey(treeUri) && !revoked.contains(treeUri) && !released.contains(treeUri);
  }

  @override
  Future<void> releaseGrant(String treeUri) async {
    calls.add('releaseGrant:$treeUri');
    released.add(treeUri);
  }

  @override
  Future<String> createFile(String treeUri, String name, Uint8List bytes) async {
    calls.add('createFile:$name');
    _need(treeUri);
    if (failWrites) throw const StorageException(StorageErrorCode.io, 'write failed');
    final folder = folders[treeUri];
    if (folder == null) throw const StorageException(StorageErrorCode.grantLost);
    // Like SAF: a clashing name is renamed, never overwritten.
    var finalName = name;
    var n = 1;
    final taken = folder.values.map((f) => f.name).toSet();
    while (taken.contains(finalName)) {
      final dot = name.lastIndexOf('.');
      finalName = dot < 0 ? '$name ($n)' : '${name.substring(0, dot)} ($n)${name.substring(dot)}';
      n++;
    }
    return seed(treeUri, finalName, Uint8List.fromList(bytes), modified: now());
  }

  @override
  Future<List<FolderFile>> listFiles(String treeUri) async {
    calls.add('listFiles:$treeUri');
    _need(treeUri);
    return List.unmodifiable((folders[treeUri] ?? const {}).values);
  }

  @override
  Future<void> deleteFile(String docUri) async {
    calls.add('deleteFile:$docUri');
    for (final entry in folders.entries) {
      if (entry.value.containsKey(docUri)) {
        _need(entry.key);
        entry.value.remove(docUri);
        contents.remove(docUri);
        return;
      }
    }
    throw const StorageException(StorageErrorCode.io, 'no such file');
  }

  @override
  Future<PickedFile?> pickFile({required int maxBytes}) async {
    calls.add('pickFile:$maxBytes');
    _pickGuard();
    final pick = filePicks.isEmpty ? null : filePicks.removeAt(0);
    if (pick != null && pick.bytes.length > maxBytes) {
      throw const StorageException(StorageErrorCode.tooLarge);
    }
    return pick;
  }

  @override
  Future<bool> openUrl(String url) async {
    calls.add('openUrl:$url');
    if (!AppConstants.allowedUrls.contains(url)) return false;
    openedUrls.add(url);
    return true;
  }
}
