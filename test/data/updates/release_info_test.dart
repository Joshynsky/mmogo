// ignore_for_file: text_direction_code_point_in_literal
// B25: strict parse of the GitHub "latest release" body and the version compare.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/release_info.dart';

String body(Object? tag, {Map<String, Object?> extra = const {}}) =>
    jsonEncode({'tag_name': tag, ...extra});

void main() {
  group('tag_name accept and reject table', () {
    for (final t in ['v1.2.3', '1.2.3', '0.1.2', 'v10.20.30', '9999.9999.9999']) {
      test('accepts $t', () => expect(ReleaseInfo.tryParse(body(t))?.tag, t));
    }
    for (final t in [
      '1.2',
      '1.2.3-rc1',
      '1.2.3.4',
      'v1.2.3+5',
      'V1.2.3',
      '10000.1.1',
      'a.b.c',
      '',
      ' 1.2.3',
      '1.2.3\n',
      'latest',
    ]) {
      test('rejects ${jsonEncode(t)}', () => expect(ReleaseInfo.tryParse(body(t)), isNull));
    }
    for (final t in [null, 123, 1.2, true, ['1.2.3'], {'a': 1}]) {
      test('rejects wrong type $t', () => expect(ReleaseInfo.tryParse(body(t)), isNull));
    }
  });

  group('draft and prerelease', () {
    test('draft true rejected', () {
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'draft': true})), isNull);
    });
    test('prerelease true rejected', () {
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'prerelease': true})), isNull);
    });
    test('wrong-typed flags rejected', () {
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'draft': 'no'})), isNull);
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'prerelease': 0})), isNull);
    });
    test('explicit false accepted', () {
      expect(
        ReleaseInfo.tryParse(body('1.2.3', extra: {'draft': false, 'prerelease': false})),
        isNotNull,
      );
    });
  });

  group('shape and bad input never throw', () {
    for (final b in ['', 'not json', '[]', '"x"', '123', 'null', '{', '{"tag_name":', '{}']) {
      test('null for ${jsonEncode(b)}', () => expect(ReleaseInfo.tryParse(b), isNull));
    }
    test('malformed UTF-8 bytes rejected', () {
      expect(ReleaseInfo.tryParseBytes([0x7B, 0xFF, 0xFE, 0x7D]), isNull);
    });
    test('valid UTF-8 bytes parse', () {
      expect(ReleaseInfo.tryParseBytes(utf8.encode(body('v1.0.0', extra: {'body': 'hé'})))?.notes, 'hé');
    });
  });

  group('notes and ignored fields', () {
    test('body is sanitised; a non-string body becomes empty', () {
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'body': 'a‮b\u0000'}))!.notes, 'ab');
      expect(ReleaseInfo.tryParse(body('1.2.3', extra: {'body': 5}))!.notes, '');
      expect(ReleaseInfo.tryParse(body('1.2.3'))!.notes, '');
    });
    test('URL fields are never carried into the result', () {
      final info = ReleaseInfo.tryParse(body('1.2.3', extra: {
        'html_url': 'https://evil.example/',
        'assets': [
          {'browser_download_url': 'https://evil.example/a.apk'}
        ],
        'body': 'notes',
      }))!;
      expect(info.tag, '1.2.3');
      expect(info.notes, 'notes');
      expect(info.toString(), isNot(contains('evil')));
    });
  });

  group('version compare', () {
    test('numeric, not textual', () {
      expect(ReleaseInfo.isNewerVersion('0.10.0', '0.9.0'), isTrue);
      expect(ReleaseInfo.isNewerVersion('0.1.10', '0.1.9'), isTrue);
      expect(ReleaseInfo.isNewerVersion('1.0.0', '0.99.99'), isTrue);
    });
    test('equal and older are not newer', () {
      expect(ReleaseInfo.isNewerVersion('0.1.1', '0.1.1'), isFalse);
      expect(ReleaseInfo.isNewerVersion('v0.1.1', '0.1.1'), isFalse);
      expect(ReleaseInfo.isNewerVersion('0.1.0', '0.1.1'), isFalse);
      expect(ReleaseInfo.isNewerVersion('0.0.9', '0.1.0'), isFalse);
    });
    test('unparseable installed version means not newer', () {
      expect(ReleaseInfo.isNewerVersion('9.9.9', 'junk'), isFalse);
    });
    test('isNewerThan on an instance', () {
      final i = ReleaseInfo.tryParse(body('v0.2.0'))!;
      expect(i.isNewerThan('0.1.1'), isTrue);
      expect(i.isNewerThan('0.2.0'), isFalse);
      expect(i.versionParts, [0, 2, 0]);
    });
  });
}
