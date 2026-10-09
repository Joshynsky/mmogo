// §AUTOREAD.FLAG, standard side: without the define the feature is not compiled.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';

void main() {
  test('kAutoReadCompiled is false by default (standard build)', () {
    expect(kAutoReadCompiled, isFalse);
  });
}
