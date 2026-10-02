// ignore_for_file: text_direction_code_point_in_literal
// B25: UpdateCheckClient against a loopback HttpServer (never the real
// GitHub). The URL override, timeout and size cap are the test seams.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/update_check_client.dart';

class _Server {
  _Server._(this.server);
  final HttpServer server;
  final requests = <HttpRequest>[];
  final headerDumps = <Map<String, List<String>>>[];
  final paths = <String>[];

  static Future<_Server> start(Future<void> Function(HttpRequest) handler) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final w = _Server._(s);
    s.listen((req) async {
      w.requests.add(req);
      w.paths.add(req.uri.toString());
      final h = <String, List<String>>{};
      req.headers.forEach((n, v) => h[n] = v);
      w.headerDumps.add(h);
      try {
        await handler(req);
      } catch (_) {}
    });
    return w;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/repos/Joshynsky/mmogo/releases/latest');
  Future<void> close() => server.close(force: true);
}

Future<void> _ok(HttpRequest r, String body) async {
  r.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(body);
  await r.response.close();
}

const _goodBody = '{"tag_name":"v0.2.0","body":"Hello","draft":false,"prerelease":false}';

void main() {
  final servers = <_Server>[];
  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
  });
  Future<_Server> serve(Future<void> Function(HttpRequest) h) async {
    final s = await _Server.start(h);
    servers.add(s);
    return s;
  }

  test('default_uri_is_https_api_github_no_query', () {
    final u = UpdateCheckClient.releasesUrl;
    expect(u.scheme, 'https');
    expect(u.host, 'api.github.com');
    expect(u.path, '/repos/Joshynsky/mmogo/releases/latest');
    expect(u.hasQuery, isFalse);
    expect(u.hasFragment, isFalse);
    expect(u.userInfo, isEmpty);
    expect(UpdateCheckClient.userAgent, 'mmogo');
  });

  test('sends_exactly_one_request_with_host_and_user_agent_mmogo_only', () async {
    final s = await serve((r) => _ok(r, _goodBody));
    final info = await UpdateCheckClient(urlOverride: s.url).fetchLatest();
    expect(info.tag, 'v0.2.0');
    expect(info.notes, 'Hello');
    expect(s.requests, hasLength(1));
    expect(s.requests.single.method, 'GET');
    expect(s.paths.single, '/repos/Joshynsky/mmogo/releases/latest'); // no query
    final h = s.headerDumps.single;
    expect(h['user-agent'], ['mmogo']);
    expect(h['host'], isNotNull);
    final extra = h.keys.toSet()..removeAll({'host', 'user-agent'});
    // Anything beyond Host and User-Agent must be transport framing only.
    expect(extra.difference({'connection'}), isEmpty, reason: 'headers: $h');
    for (final bad in ['cookie', 'authorization', 'x-api-key', 'accept-encoding', 'referer']) {
      expect(h.containsKey(bad), isFalse, reason: bad);
    }
  });

  test('redirect_302_is_failure_and_second_port_never_hit', () async {
    final target = await serve((r) => _ok(r, _goodBody));
    final s = await serve((r) async {
      r.response
        ..statusCode = 302
        ..headers.set('location', target.url.toString());
      await r.response.close();
    });
    await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(anything));
    expect(s.requests, hasLength(1));
    expect(target.requests, isEmpty);
  });

  for (final code in [301, 403, 500, 204]) {
    test('status $code is failure', () async {
      final s = await serve((r) async {
        r.response.statusCode = code;
        await r.response.close();
      });
      await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(anything));
    });
  }

  test('B27: status 404 throws NoReleaseYetException (no release published yet), nothing else', () async {
    final s = await serve((r) async {
      r.response.statusCode = 404;
      await r.response.close();
    });
    await expectLater(
      UpdateCheckClient(urlOverride: s.url).fetchLatest(),
      throwsA(isA<NoReleaseYetException>()),
    );
    expect(s.requests, hasLength(1));
  });

  for (final code in [403, 500]) {
    test('B27: status $code is NOT NoReleaseYetException', () async {
      final s = await serve((r) async {
        r.response.statusCode = code;
        await r.response.close();
      });
      await expectLater(
        UpdateCheckClient(urlOverride: s.url).fetchLatest(),
        throwsA(isNot(isA<NoReleaseYetException>())),
      );
    });
  }

  test('stalled_server_times_out', () async {
    final s = await serve((r) async {
      await Completer<void>().future; // never answers
    });
    final sw = Stopwatch()..start();
    await expectLater(
      UpdateCheckClient(urlOverride: s.url, timeout: const Duration(milliseconds: 300)).fetchLatest(),
      throwsA(isA<TimeoutException>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('headers_then_slow_body_times_out (the timeout covers the body read)', () async {
    final s = await serve((r) async {
      r.response.statusCode = 200;
      r.response.write('{"tag_name":');
      await r.response.flush();
      await Completer<void>().future;
    });
    await expectLater(
      UpdateCheckClient(urlOverride: s.url, timeout: const Duration(milliseconds: 300)).fetchLatest(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('connection_refused_is_failure (offline)', () async {
    final s = await _Server.start((r) async {});
    final url = s.url;
    await s.close();
    await expectLater(UpdateCheckClient(urlOverride: url).fetchLatest(), throwsA(isA<SocketException>()));
  });

  test('300kb_body_aborted_near_cap (declared length)', () async {
    final s = await serve((r) => _ok(r, '{"tag_name":"1.2.3","body":"${'a' * (300 * 1024)}"}'));
    await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(isA<HttpException>()));
  });

  test('chunked body over the cap is aborted while streaming (no Content-Length)', () async {
    var sent = 0;
    final s = await serve((r) async {
      r.response
        ..statusCode = 200
        ..headers.chunkedTransferEncoding = true;
      final chunk = 'a' * 16384;
      try {
        for (var i = 0; i < 400; i++) {
          r.response.write(chunk);
          await r.response.flush();
          sent += chunk.length;
        }
      } catch (_) {}
      await r.response.close().catchError((_) {});
    });
    await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(isA<HttpException>()));
    expect(sent, lessThan(400 * 16384), reason: 'the client must stop reading, not drain it all');
  });

  test('body just under the cap is accepted', () async {
    const pad = 200 * 1024;
    final s = await serve((r) => _ok(r, jsonEncode({'tag_name': '1.2.3', 'x': 'a' * pad, 'body': 'ok'})));
    expect((await UpdateCheckClient(urlOverride: s.url).fetchLatest()).notes, 'ok');
  });

  for (final entry in {
    'bad json': 'not json{',
    'empty body': '',
    'array': '[]',
    'wrong tag': '{"tag_name":"1.2"}',
    'prerelease': '{"tag_name":"1.2.3","prerelease":true}',
    'draft': '{"tag_name":"1.2.3","draft":true}',
  }.entries) {
    test('200 with ${entry.key} fails (404_and_bad_json_fail_silently)', () async {
      final s = await serve((r) => _ok(r, entry.value));
      await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(isA<FormatException>()));
    });
  }

  test('malformed UTF-8 body fails', () async {
    final s = await serve((r) async {
      r.response
        ..statusCode = 200
        ..add([0x7B, 0xFF, 0xFE, 0x7D]);
      await r.response.close();
    });
    await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(isA<FormatException>()));
  });

  test('hostile release notes come out sanitised', () async {
    final s = await serve((r) => _ok(
          r,
          jsonEncode({'tag_name': 'v0.2.0', 'body': 'Click‮ gpj.exe \u0000 https://evil.example/a.apk'}),
        ));
    final info = await UpdateCheckClient(urlOverride: s.url).fetchLatest();
    expect(info.notes, 'Click gpj.exe  https://evil.example/a.apk');
  });

  test('a gzip-claiming response is not decoded (autoUncompress off) and fails parse', () async {
    final s = await serve((r) async {
      r.response
        ..statusCode = 200
        ..headers.set('content-encoding', 'gzip')
        ..add(gzip.encode(utf8.encode(_goodBody)));
      await r.response.close();
    });
    await expectLater(UpdateCheckClient(urlOverride: s.url).fetchLatest(), throwsA(isA<FormatException>()));
  });
}
