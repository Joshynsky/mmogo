import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'release_info.dart';

/// What `UpdateCheckService` needs from the network layer. The real
/// implementation is [UpdateCheckClient]; tests pass a fake.
abstract class UpdateCheckSource {
  /// The newest published release, or throws on ANY failure (offline, TLS,
  /// timeout, non-200, too large, not JSON, not a usable release). A 404
  /// throws [NoReleaseYetException] (no release published yet).
  Future<ReleaseInfo> fetchLatest();
}

/// GitHub answered 404: the repository has no published release yet. The
/// service counts this as a successful check with nothing new (ruling
/// B25/B26 no. 2), so a repo without a release does not cause a request on
/// every launch.
class NoReleaseYetException implements Exception {
  const NoReleaseYetException();

  @override
  String toString() => 'NoReleaseYetException';
}

/// The app's ONE outbound network call (criteria 14 to 17): a single GET to
/// the constant GitHub releases URL. GitHub sees the IP address and that the
/// request comes from the mmogo app; nothing else is sent (no identifier, no
/// version, no query string, no cookies, no Authorization).
///
/// This is the only file in `lib/` allowed to construct an `HttpClient`
/// (`test/static/no_extra_network_test.dart` pins that).
class UpdateCheckClient implements UpdateCheckSource {
  /// [urlOverride], [timeout] and [maxBytes] exist so tests can aim at a
  /// loopback server and shorten waits; production passes none of them.
  UpdateCheckClient({
    @visibleForTesting Uri? urlOverride,
    @visibleForTesting Duration timeout = defaultTimeout,
    @visibleForTesting int maxBytes = maxBodyBytes,
  })  : _url = urlOverride ?? releasesUrl,
        _timeout = timeout,
        _maxBytes = maxBytes;

  static final Uri releasesUrl =
      Uri.parse('https://api.github.com/repos/Joshynsky/mmogo/releases/latest');

  /// Exactly this, with no app version (Phase 3 binding).
  static const userAgent = 'mmogo';

  static const defaultTimeout = Duration(seconds: 10);
  static const maxBodyBytes = 256 * 1024;

  final Uri _url;
  final Duration _timeout;
  final int _maxBytes;

  @override
  Future<ReleaseInfo> fetchLatest() async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..userAgent = userAgent
      ..autoUncompress = false;
    try {
      final bytes = await _get(client).timeout(_timeout);
      final info = ReleaseInfo.tryParseBytes(bytes);
      if (info == null) {
        throw const FormatException('not a usable release');
      }
      return info;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _get(HttpClient client) async {
    final request = await client.getUrl(_url);
    request.followRedirects = false;
    // dart:io adds Accept-Encoding: gzip on its own; the request carries only
    // Host and User-Agent, so take it off.
    request.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    final response = await request.close();
    if (response.statusCode == HttpStatus.notFound) {
      throw const NoReleaseYetException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('status ${response.statusCode}');
    }
    if (response.contentLength > _maxBytes) {
      throw const HttpException('body too large');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBytes) {
        throw const HttpException('body too large');
      }
    }
    return bytes;
  }
}
