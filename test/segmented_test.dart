import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置页的主题 / 列数用 SegmentedButton：先在测试里验证这套布局能点。
/// 真机第一次验证时点它没反应，所以把布局原样搬进来测一遍。
void main() {
  testWidgets('分段按钮在 ListView + Card 里可点击', (tester) async {
    var mode = ThemeMode.dark;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('主题'),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('跟随系统'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('深色'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('浅色'),
                                ),
                              ],
                              selected: {mode},
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onSelectionChanged: (value) =>
                                  setState(() => mode = value.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(mode, ThemeMode.light);
  });
}
