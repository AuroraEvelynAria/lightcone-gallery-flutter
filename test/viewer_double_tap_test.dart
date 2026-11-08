import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/viewer_screen.dart';

void main() {
  testWidgets('双击横图会放大到铺满屏高，再双击还原', (tester) async {
    // 375 × 812 逻辑像素，和真机一致
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewerScreen(
          items: [
            ViewerItem(
              path: '/nonexistent.png',
              title: 'wide',
              aspectRatio: 6605 / 1858,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    InteractiveViewer viewer() =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    PageView pageView() => tester.widget<PageView>(find.byType(PageView));

    expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(pageView().physics, isA<PageScrollPhysics>());

    // 两次点击间隔要在 kDoubleTapTimeout 内
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    // 先让双击回调落地，再推进 240ms 的缩放补间
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final zoomed = viewer().transformationController!.value.getMaxScaleOnAxis();
    expect(zoomed, greaterThan(2), reason: '横图应该明显放大');
    expect(zoomed, closeTo(7.7, 0.3));
    // 放大后不能再让 PageView 抢横向拖动，否则平移图片会变成翻页
    expect(pageView().physics, isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(pageView().physics, isA<PageScrollPhysics>());
  });

  testWidgets('双指张开能放大，PageView 不抢手势', (tester) async {
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewerScreen(
          items: [
            ViewerItem(
              path: '/nonexistent-1.png',
              title: '1',
              aspectRatio: 0.75,
            ),
            ViewerItem(
              path: '/nonexistent-2.png',
              title: '2',
              aspectRatio: 0.75,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    final controller = viewer.transformationController!;
    PageView pageView() => tester.widget<PageView>(find.byType(PageView));
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(pageView().physics, isA<PageScrollPhysics>());

    // 两根手指从 100px 间距张到 260px 间距
    // 真机上通常是先落一根、再落第二根；中间隔一小段时间模拟 PageView
    // 已经开始跟踪第一根手指的情况。
    final first = await tester.startGesture(const Offset(150, 400), pointer: 1);
    await tester.pump(const Duration(milliseconds: 100));
    final second = await tester.startGesture(const Offset(250, 400), pointer: 2);
    await tester.pump();
    // 第二根手指一落下，PageView 就该先让路，不能等到 scale 变化
    expect(pageView().physics, isA<NeverScrollableScrollPhysics>());
    await first.moveBy(const Offset(-80, 0));
    await second.moveBy(const Offset(80, 0));
    await tester.pump();

    final scale = controller.value.getMaxScaleOnAxis();
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(scale, greaterThan(1.2), reason: '双指张开应该放大');
  });
}
