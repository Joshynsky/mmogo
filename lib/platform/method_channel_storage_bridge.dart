
import 'package:flutter/services.dart';

import '../app_constants.dart';
import 'storage_bridge.dart';

/// The real [StorageBridge], over `MethodChannel('app.mmogo/storage')`.
class MethodChannelStorageBridge implements StorageBridge {
  MethodChannelStorageBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('app.mmogo/storage');

  final MethodChannel _channel;

  /// Runs a channel call, mapping every failure to [StorageException].
  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw StorageException(StorageErrorCode.fromWire(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw StorageException(StorageErrorCode.io, e.message);
    }
  }

  StorageException _bad(String what) => StorageException(StorageErrorCode.io, 'unexpected reply to $what');

  @override
  Future<PickedFolder?> pickFolder() async {
    try {
      final m = await _call<Map<Object?, Object?>>('pickFolder');
      if (m == null) return null;
      final uri = m['uri'];
      final name = m['name'];
      if (uri is! String || uri.isEmpty) throw _bad('pickFolder');
      return PickedFolder(uri: uri, name: name is String ? name : '');
    } on StorageException catch (e) {
      if (e.code == StorageErrorCode.cancelled) return null;
      rethrow;
    }
  }

  @override
  Future<bool> hasWriteGrant(String treeUri) async =>
      (await _call<bool>('hasWriteGrant', {'treeUri': treeUri})) ?? false;

  @override
  Future<void> releaseGrant(String treeUri) => _call<void>('releaseGrant', {'treeUri': treeUri});

  @override
  Future<String> createFile(String treeUri, String name, Uint8List bytes) async {
    final uri = await _call<String>('createFile', {'treeUri': treeUri, 'name': name, 'bytes': bytes});
    if (uri == null || uri.isEmpty) throw _bad('createFile');
    return uri;
  }

  @override
  Future<List<FolderFile>> listFiles(String treeUri) async {
    final rows = await _call<List<Object?>>('listFiles', {'treeUri': treeUri});
    if (rows == null) throw _bad('listFiles');
    final out = <FolderFile>[];
    for (final r in rows) {
      if (r is! Map) throw _bad('listFiles');
      final name = r['name'];
      final uri = r['uri'];
      if (name is! String || uri is! String) throw _bad('listFiles');
      final size = r['size'];
      final modified = r['lastModified'];
      out.add(FolderFile(
        name: name,
        uri: uri,
        size: size is int ? size : 0,
        lastModified: DateTime.fromMillisecondsSinceEpoch(modified is int ? modified : 0, isUtc: true),
      ));
    }
    return out;
  }

  @override
  Future<void> deleteFile(String docUri) => _call<void>('deleteFile', {'docUri': docUri});

  @override
  Future<PickedFile?> pickFile({required int maxBytes}) async {
    try {
      final m = await _call<Map<Object?, Object?>>('pickFile', {'maxBytes': maxBytes});
      if (m == null) return null;
      final bytes = m['bytes'];
      if (bytes is! Uint8List) throw _bad('pickFile');
      final name = m['name'];
      return PickedFile(name: name is String ? name : '', bytes: bytes);
    } on StorageException catch (e) {
      if (e.code == StorageErrorCode.cancelled) return null;
      rethrow;
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    // Defence in depth: Kotlin enforces the same allowlist.
    if (!AppConstants.allowedUrls.contains(url)) return false;
    return (await _call<bool>('openUrl', {'url': url})) ?? false;
  }
}
