import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/brand.dart';
import 'package:lightcone_flutter/ui/splash_screen.dart';

void main() {
  testWidgets('开屏在最窄的常见屏宽上不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    // 开屏有 900ms 的淡入 + 不确定进度条（不能 pumpAndSettle）
    await tester.pump(const Duration(milliseconds: 950));

    expect(find.text('光锥图库'), findsOneWidget);
    expect(find.text('LIGHTCONE GALLERY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('光锥标记在标题栏尺寸下也能画', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: LightConeMark(size: 40))),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
