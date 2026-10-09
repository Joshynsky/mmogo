// §AUTOREAD.FLAG, autoread side. Runs only in the second invocation:
//   flutter test --dart-define=MMOGO_AUTOREAD=true --tags autoread
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';

void main() {
  // Skipped (not failed) when the define is absent, so the default
  // `flutter test` run, which also loads tagged files, stays green.
  test(
    'kAutoReadCompiled is true when built with MMOGO_AUTOREAD=true',
    () => expect(kAutoReadCompiled, isTrue),
    skip: kAutoReadCompiled ? null : 'needs --dart-define=MMOGO_AUTOREAD=true',
  );
}
