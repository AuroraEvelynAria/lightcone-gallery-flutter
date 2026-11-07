import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/viewer_screen.dart';

void main() {
  // 375 × 812：竖屏手机的逻辑尺寸（与真机 1220×2712 @3.25 一致）
  const screen = Size(375, 812);

  group('双击铺满屏高的倍率', () {
    test('16:9 约 3.85 倍', () {
      expect(
        fillHeightScale(16 / 9, screen),
        closeTo(812 / (375 / (16 / 9)), 0.01),
      );
    });

    test('3.55:1 全景约 7.7 倍', () {
      expect(
        fillHeightScale(6605 / 1858, screen),
        closeTo(812 / (375 / (6605 / 1858)), 0.01),
      );
    });

    test('竖图至少 2 倍，不会几乎不动', () {
      expect(fillHeightScale(0.75, screen), 2);
    });

    test('比例未知时给 2 倍', () {
      expect(fillHeightScale(0, screen), 2);
    });
  });
}
