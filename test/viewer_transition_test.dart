import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/viewer_screen.dart';

/// 检视器进出场动画的行为约束。
///
/// 钉的是「动画真的在跑、起止值对、退出是反向」。
/// 手感（时长、曲线）靠真机看，不靠断言。
void main() {
  const items = [
    ViewerItem(path: '/nonexistent.png', title: 't', aspectRatio: 0.75),
  ];

  /// 打开检视器。
  ///
  /// 第一次 pump 处理 push（插入路由），第二次 pump 才把页面真正建出来；
  /// 两次都是零时长，所以动画进度停在 t=0，可以断言起点值。
  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  viewerRoute(items: items, initialIndex: 0),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<ScaleTransition>(
        find.byKey(const ValueKey(viewerTransitionScaleKey)),
      )
      .scale
      .value;

  double fadeOf(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.byKey(const ValueKey(viewerTransitionFadeKey)),
      )
      .opacity
      .value;

  testWidgets('进场：从 kViewerEnterScale 放大到 1，同时由透明转不透明', (tester) async {
    await openViewer(tester);

    expect(
      scaleOf(tester),
      closeTo(kViewerEnterScale, 0.001),
      reason: '进场起点应该是轻微缩小',
    );
    expect(fadeOf(tester), closeTo(0, 0.001), reason: '起点应该全透明');

    // 中点：两端之间，说明确实在补间而不是瞬切
    await tester.pump(const Duration(milliseconds: 130));
    final mid = scaleOf(tester);
    expect(mid, greaterThan(kViewerEnterScale));
    expect(mid, lessThan(1));
    expect(fadeOf(tester), inExclusiveRange(0, 1));

    // 走完进场时长后到位
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(tester), closeTo(1, 0.001));
    expect(fadeOf(tester), closeTo(1, 0.001));

    // 排掉原图升级的 600ms 定时器，否则测试结束会报 pending timer
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('退出：反向缩回并淡出，结束后路由移除', (tester) async {
    await openViewer(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaleOf(tester), closeTo(1, 0.001));

    Navigator.of(tester.element(find.byType(ViewerScreen))).pop();
    await tester.pump();

    // 退出刚开始：仍接近全尺寸
    expect(scaleOf(tester), greaterThan(0.9));

    // 退出中点：已经缩下去、也淡了一半以上
    await tester.pump(const Duration(milliseconds: 100));
    final mid = scaleOf(tester);
    expect(mid, lessThan(1));
    expect(mid, greaterThanOrEqualTo(kViewerEnterScale - 0.001));
    expect(fadeOf(tester), lessThan(1));

    // 走完退场时长后完全消失
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ViewerScreen), findsNothing, reason: '退出动画结束路由应已移除');
  });

  testWidgets('退场比进场快：退出是「回到刚才」，不该拖沓', (tester) async {
    expect(
      kViewerExitDuration.inMilliseconds,
      lessThan(kViewerEnterDuration.inMilliseconds),
    );
  });
}
