import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/byte_size.dart';

void main() {
  group('formatByteSize', () {
    test('null (unknown) renders as an em dash', () => expect(formatByteSize(null), '—'));
    test('under 1 KB shows raw bytes', () => expect(formatByteSize(512), '512 bytes'));
    test('KB with one decimal', () => expect(formatByteSize(40960), '40.0 KB'));
    test('fractional KB', () => expect(formatByteSize(1536), '1.5 KB'));
    test('MB at and above 1024 KB', () => expect(formatByteSize(1024 * 1024 * 3 ~/ 2), '1.5 MB'));
  });
}
