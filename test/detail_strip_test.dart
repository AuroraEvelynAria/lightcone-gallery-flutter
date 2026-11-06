import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 详情页长图是 SliverList：每个 item 的高度必须由自己撑开。
/// 之前 R-18 角标的 Stack 只有 Positioned 子节点，在无界高度下算不出尺寸，
/// 整条 sliver 布局失败（真机白屏）。这里把原结构搬进来守着。
void main() {
  testWidgets('长图 sliver 能正常布局', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverList.separated(
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  Widget content = SizedBox(
                    width: 300,
                    height: 400,
                    child: ColoredBox(
                      color: Colors.red,
                      child: Center(child: Text('page $index')),
                    ),
                  );
                  if (index == 0) {
                    content = Stack(
                      clipBehavior: Clip.none,
                      children: [
                        content,
                        const Positioned(
                          left: 10,
                          top: 10,
                          child: Text('R-18'),
                        ),
                      ],
                    );
                  }
                  return content;
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 200, child: Text('info'))),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('R-18'), findsOneWidget);
  });
}
