import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/tone.dart';

/// 深浅色切换时界面不该有位置变化。
///
/// 踩过的坑：浅色主题不画描边、深色画 1px 描边，而 BoxDecoration 的 border
/// 是以 padding 的形式挤窄内容区的 —— 切主题时卡片里的内容整体左右各缩
/// 1px（3.25 倍屏上是 3 个物理像素，肉眼能看出「跳了一下」）。所以描边必
/// 须两端都占位：浅色用完全透明的 border，而不是不画。
void main() {
  Future<Rect> contentRect(WidgetTester tester, Brightness brightness) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          extensions: <ThemeExtension<dynamic>>[
            ToneTokens.of(
              brightness == Brightness.dark
                  ? kArchiveTone.dark
                  : kArchiveTone.light,
              brightness,
            ),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: Builder(
                builder: (context) => Container(
                  decoration: softCardDecoration(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [SizedBox(key: key, height: 40)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // MaterialApp 内部用 AnimatedTheme 过渡主题，不 settle 会读到上一帧的
    // 主题 —— 第一版测试就是在这里误判成「深浅色没有区别」。
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(key));
  }

  test('深浅色之间是插值，不是硬切', () {
    final light = ToneTokens.of(kArchiveTone.light, Brightness.light);
    final dark = ToneTokens.of(kArchiveTone.dark, Brightness.dark);
    final mid = light.lerp(dark, 0.5);

    // 卡片的每一层都得落在两端之间 —— 之前 ToneTokens.lerp 直接返回
    // this，主题在渐变、令牌是硬切，看着就是「一半丝滑一半跳帧」。
    expect(mid.card, isNot(light.card));
    expect(mid.card, isNot(dark.card));
    expect(mid.cardLine, isNot(light.cardLine));
    expect(mid.set.bg, isNot(light.set.bg));
    // 注意别拿 accent 断言：ARCHIVE 的明暗两套 accent 是同一个 #FF7A01
    // （强调色本来就不随明暗变），插值后当然还是它。
    expect(mid.set.kase, isNot(light.set.kase));

    // 从「浅色有投影」过渡到「深色无投影」，中点必须还剩一层更淡的影子，
    // 否则深色那一侧会把投影一次性抽掉，卡片会「噗」地塌一下。
    expect(mid.cardShadow, isNotEmpty);
    expect(
      mid.cardShadow.first.color.a,
      inExclusiveRange(0.0, light.cardShadow.first.color.a),
    );
  });

  testWidgets('切主题时卡片颜色逐帧变化，不是一帧跳过去', (tester) async {
    Widget app(ThemeMode mode) => MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: <ThemeExtension<dynamic>>[
              ToneTokens.of(kArchiveTone.light, Brightness.light),
            ],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            extensions: <ThemeExtension<dynamic>>[
              ToneTokens.of(kArchiveTone.dark, Brightness.dark),
            ],
          ),
          themeMode: mode,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => DecoratedBox(
                  key: const ValueKey('card'),
                  decoration: softCardDecoration(context),
                  child: const SizedBox(width: 120, height: 60),
                ),
              ),
            ),
          ),
        );

    Color cardColor() => (tester
            .widget<DecoratedBox>(find.byKey(const ValueKey('card')))
            .decoration as BoxDecoration)
        .color!;

    await tester.pumpWidget(app(ThemeMode.light));
    await tester.pumpAndSettle();
    final start = cardColor();

    await tester.pumpWidget(app(ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 130));
    final middle = cardColor();

    await tester.pumpAndSettle();
    final end = cardColor();

    expect(middle, isNot(start), reason: '过渡中途应该是中间色');
    expect(middle, isNot(end), reason: '过渡中途不能直接是终点色');
  });

  testWidgets('深浅主题下卡片内容的位置与尺寸必须一致', (tester) async {
    final light = await contentRect(tester, Brightness.light);
    final dark = await contentRect(tester, Brightness.dark);

    expect(dark.size, light.size, reason: '描边不能改变卡片内容的尺寸');
    expect(dark.topLeft, light.topLeft, reason: '描边不能把卡片内容推位移');
  });
}
