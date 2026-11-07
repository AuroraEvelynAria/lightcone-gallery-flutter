import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';
import 'package:lightcone_flutter/ui/page_stage.dart';

/// 1×1 透明 PNG：只用来让 Image 有合法数据，尺寸断言不依赖它。
final _onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

ArtworkRow _page(int width, int height) => ArtworkRow(
      id: 1,
      pid: '147023216',
      originalPath: '/nonexistent.png',
      page: 0,
      width: width,
      height: height,
    );

void main() {
  group('PageStage', () {
    test('竖图按原比例铺满宽度', () {
      final stage = PageStage.compute(
        screenWidth: 375,
        screenHeight: 812,
        aspectRatio: 0.75,
        appBarBottom: 88,
        first: true,
      );
      expect(stage.wide, isFalse);
      expect(stage.height, 500);
      expect(stage.topInset, 0, reason: '竖图保持沉浸式，钻到状态栏下是设计');
      expect(stage.ambient, isFalse);
    });

    test('第一页 16:9 让出顶栏，舞台按原比例', () {
      final stage = PageStage.compute(
        screenWidth: 375,
        screenHeight: 812,
        aspectRatio: 16 / 9,
        appBarBottom: 88,
        first: true,
      );
      expect(stage.wide, isTrue);
      expect(stage.topInset, 88);
      expect(stage.height, closeTo(375 / (16 / 9), 0.01));
      expect(stage.ambient, isTrue, reason: '让位区要有模糊底');
      expect(stage.totalHeight, closeTo(88 + 375 / (16 / 9), 0.01));
    });

    test('全景图撑到 0.56 屏宽，并铺模糊底', () {
      final stage = PageStage.compute(
        screenWidth: 375,
        screenHeight: 812,
        aspectRatio: 6605 / 1858,
        appBarBottom: 88,
        first: false,
      );
      expect(stage.wide, isTrue);
      expect(stage.topInset, 0);
      expect(stage.height, closeTo(375 * 0.56, 0.01));
      expect(stage.ambient, isTrue);
      // 横图的真图仍然按宽度完整显示，只是上下有环境底
      expect(375 / (6605 / 1858), lessThan(stage.height));
    });

    test('横屏可视高度矮时，舞台不超过可视高度的 72%', () {
      final stage = PageStage.compute(
        screenWidth: 812,
        screenHeight: 375,
        aspectRatio: 6605 / 1858,
        appBarBottom: 64,
        first: true,
      );
      expect(stage.height, closeTo(375 * 0.72, 0.01));
      expect(stage.topInset, 64);
    });
  });

  testWidgets('第一页横图从顶栏下方开始，且整块可点', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ArtworkPageTile(
              page: _page(6605, 1858),
              screenWidth: 375,
              screenHeight: 812,
              appBarBottom: 88,
              first: true,
              providerFor: (_) => MemoryImage(_onePixel),
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 375 * 0.56 = 210（全景图的舞台高度），再加 88 的顶栏让位
    expect(tester.getSize(find.byType(ArtworkPageTile)).height, closeTo(298, 0.5));
    final sharpTop = tester.getTopLeft(find.byKey(const ValueKey('page-sharp'))).dy;
    expect(sharpTop, greaterThanOrEqualTo(88),
        reason: '真图不能钻到状态栏/顶栏下面');

    await tester.tap(find.byType(ArtworkPageTile));
    expect(taps, 1);
  });

  testWidgets('竖图第一页保持原来的满幅高度', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ArtworkPageTile(
              page: _page(1200, 1600),
              screenWidth: 375,
              screenHeight: 812,
              appBarBottom: 88,
              first: true,
              providerFor: (_) => MemoryImage(_onePixel),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(ArtworkPageTile)).height, 500);
  });
}
