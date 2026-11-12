import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/db.dart';
import 'package:lightcone_flutter/data/repository.dart';
import 'package:lightcone_flutter/data/schema.dart';
import 'package:lightcone_flutter/state/app_settings.dart';
import 'package:lightcone_flutter/state/app_state.dart';
import 'package:lightcone_flutter/ui/artwork_card.dart';
import 'package:lightcone_flutter/ui/artwork_detail_screen.dart';
import 'package:lightcone_flutter/ui/artworks_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 作品库的**桌面多选**：Ctrl 加选 / Shift 连选 / Ctrl+A 全选 / Delete 移出 /
/// Esc 退出。这些是真正会出 bug 的分支（修饰键读取、锚点连选、按键冒泡），
/// 所以跑真屏而不是只测孤立的卡片。
///
/// 数据走 sqflite FFI（真实 I/O）：首屏加载必须放在 `tester.runAsync` 里，
/// 否则 fake-async 收不到后台 isolate 的结果，`pumpAndSettle` 会一直转圈。
void main() {
  // 桌面多选只在 Windows 走（_desktop = Platform.isWindows），别在别的平台误判。
  if (!Platform.isWindows) return;

  late Repository repo;
  late AppState state;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 12,
      onCreate: (db, _) async {
        for (final sql in kSchemaV12) {
          await db.execute(sql);
        }
        await db.execute(kMediaIdsTable);
        await db.execute(kIllustAiTable);
      },
    );
    addTearDown(db.close);
    repo = Repository(LightConeDb.forTesting(db));
    // 3 个 PID，各一页；pid 越大排序越靠前（artworksPage 按 CAST(pid) DESC）
    for (final pid in ['100', '101', '102']) {
      await db.insert('artworks', {
        'pid': pid,
        'original_path': 'C:/fake/$pid.png',
        'page': 0,
        'created_at': 1,
        'width': 1000,
        'height': 1500,
      });
    }
    state = AppState(repo);
  });

  /// 挂载作品库并等首屏数据落库（真实 I/O 必须走 runAsync）。
  Future<void> pump(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppSettingsScope(
            settings: AppSettings(repo),
            child: Scaffold(body: ArtworksScreen(state: state)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(); // 落 setState
    await tester.pump();
  }

  Finder cardAt(int index) => find.byType(ArtworkCard).at(index);

  /// 按住修饰键点第 index 张卡。Ctrl 为 null 时就是普通点击。
  Future<void> tapCard(
    WidgetTester tester,
    int index, {
    LogicalKeyboardKey? hold,
  }) async {
    if (hold != null) await tester.sendKeyDownEvent(hold);
    await tester.tap(cardAt(index));
    if (hold != null) await tester.sendKeyUpEvent(hold);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
      {bool ctrl = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('三张卡都在，初始没有选择态', (tester) async {
    await pump(tester);
    expect(find.byType(ArtworkCard), findsNWidgets(3));
    expect(find.textContaining('已选'), findsNothing);
  });

  testWidgets('Ctrl 点选两张 → 进入选择态并计数', (tester) async {
    await pump(tester);
    await tapCard(tester, 0, hold: LogicalKeyboardKey.controlLeft);
    expect(find.text('已选 1'), findsOneWidget, reason: 'Ctrl 点一下应进选择态');

    await tapCard(tester, 1, hold: LogicalKeyboardKey.controlLeft);
    expect(find.text('已选 2'), findsOneWidget, reason: 'Ctrl 再点应加选');
  });

  testWidgets('Ctrl 再点已选中的卡 → 取消勾选', (tester) async {
    await pump(tester);
    await tapCard(tester, 0, hold: LogicalKeyboardKey.controlLeft);
    await tapCard(tester, 1, hold: LogicalKeyboardKey.controlLeft);
    await tapCard(tester, 1, hold: LogicalKeyboardKey.controlLeft);
    expect(find.text('已选 1'), findsOneWidget);
  });

  testWidgets('Shift 连选：从锚点一路选到目标', (tester) async {
    await pump(tester);
    await tapCard(tester, 0, hold: LogicalKeyboardKey.controlLeft); // 锚点
    await tapCard(tester, 2, hold: LogicalKeyboardKey.shiftLeft); // 连选到第 3 张
    expect(find.text('已选 3'), findsOneWidget);
  });

  testWidgets('Ctrl+A 全选，Esc 退出选择态', (tester) async {
    await pump(tester);
    await tapCard(tester, 0, hold: LogicalKeyboardKey.controlLeft); // 进选择态 + 拿焦点

    await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
    expect(find.text('已选 3'), findsOneWidget, reason: 'Ctrl+A 应全选');

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.textContaining('已选'), findsNothing, reason: 'Esc 应退出选择态');
  });

  testWidgets('Delete 在选择态弹「移出 N 件」确认框，取消后什么都没删', (tester) async {
    await pump(tester);
    await tapCard(tester, 0, hold: LogicalKeyboardKey.controlLeft);
    await tapCard(tester, 1, hold: LogicalKeyboardKey.controlLeft);

    await press(tester, LogicalKeyboardKey.delete);
    expect(find.text('移出 2 件？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump();
    expect(find.text('已选 2'), findsOneWidget, reason: '取消后应留在选择态');
    final rows = await tester.runAsync(
      () => repo.artworksPage(offset: 0, limit: 10),
    );
    expect(rows, hasLength(3), reason: '取消不该动数据');
  });

  testWidgets('桌面普通点击（无修饰键）打开详情，不进选择态', (tester) async {
    await pump(tester);
    await tapCard(tester, 0);
    // 详情页内部会异步 load 数据（真实 I/O），不能 pumpAndSettle（转圈动画不停），
    // 手动推几帧让路由转场结束。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ArtworkDetailScreen), findsOneWidget);
    expect(find.textContaining('已选'), findsNothing);
  });
}
