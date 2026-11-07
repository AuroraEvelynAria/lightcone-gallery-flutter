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

    expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 1);

    // 两次点击间隔要在 kDoubleTapTimeout 内
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 350));

    final zoomed = viewer().transformationController!.value.getMaxScaleOnAxis();
    expect(zoomed, greaterThan(2), reason: '横图应该明显放大');
    expect(zoomed, closeTo(7.7, 0.3));

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 350));

    expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 1);
  });
}
