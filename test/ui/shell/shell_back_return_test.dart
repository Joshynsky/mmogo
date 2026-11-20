// 0.2.1 QA 20-11-2026: Back from Analytics opened from Paid to returns to Paid to, not Home.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';

void main() {
  test('Paid to -> Analytics -> Back returns to Paid to, then Back goes Home', () {
    final c = PrimaryShellController(PrimaryShellController.paidToIndex);
    c.openAnalytics(Object());
    expect(c.index.value, PrimaryShellController.analyticsIndex);
    c.goBack();
    expect(c.index.value, PrimaryShellController.paidToIndex);
    c.goBack();
    expect(c.index.value, 0);
    c.dispose();
  });

  test('Home -> Analytics -> Back goes Home; a tab picked by hand forgets the return', () {
    final c = PrimaryShellController(0);
    c.openAnalytics(Object());
    c.goBack();
    expect(c.index.value, 0);
    c.select(PrimaryShellController.paidToIndex);
    c.openAnalytics(Object());
    c.select(PrimaryShellController.analyticsIndex);
    c.goBack();
    expect(c.index.value, 0);
    c.dispose();
  });
}
