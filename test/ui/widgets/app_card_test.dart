import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/ui/theme/app_colors.dart';
import 'package:mymog/ui/widgets/app_card.dart';

void main() {
  BoxDecoration deco(WidgetTester t) => t.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;

  Future<void> pump(WidgetTester t, AppPalette p) => t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: AppCard(palette: p, child: const SizedBox()),
    ),
  );

  testWidgets('AppCard shadow follows palette.deep (light), none on dark', (t) async {
    await pump(t, AppPalette.light);
    expect(deco(t).boxShadow!.single.color, AppPalette.light.deep.withValues(alpha: 0.06));

    await pump(t, AppPalette.leafLight);
    expect(deco(t).boxShadow!.single.color, AppPalette.leafLight.deep.withValues(alpha: 0.06));
    expect(deco(t).boxShadow!.single.color, isNot(AppPalette.light.deep.withValues(alpha: 0.06)));

    await pump(t, AppPalette.dark);
    expect(deco(t).boxShadow, isNull);
  });
}
