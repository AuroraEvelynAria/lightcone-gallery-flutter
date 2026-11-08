import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// 数据库门面：打开 / 建库 / 导入桌面备份。
///
/// 与 Kotlin 版的关键差异：**sqflite 就是 Android 原生 SQLite，不做 Room 那种
/// 逐列校验**，所以导入桌面备份不需要 ATTACH 搬数据 —— 校验通过后直接把文件
/// 换掉即可（桌面导出用的是 `VACUUM INTO`，是干净的单文件）。
class LightConeDb {
  LightConeDb._(this.database);

  /// 测试用：直接包装一个已经打开的数据库（FFI 临时库）。
  LightConeDb.forTesting(this.database);

  final Database database;
  static LightConeDb? _instance;

  static Future<LightConeDb> open() async {
    final existing = _instance;
    if (existing != null) return existing;

    final dbPath = await databasePath();
    final db = await openDatabase(
      dbPath,
      version: 12,
      onCreate: (db, _) async {
        final batch = db.batch();
        for (final sql in kSchemaV12) {
          batch.execute(sql);
        }
        batch.execute(kMediaIdsTable);
        batch.execute(kIllustAiTable);
        await batch.commit(noResult: true);
      },
      onOpen: (db) async {
        // 导入的桌面库没有私有表：每次打开补建（幂等）
        await db.execute(kMediaIdsTable);
        await db.execute(kIllustAiTable);
        // 桌面端同款：WAL 下两个连接短暂并发时不至于立刻报 database is locked
        await db.execute('PRAGMA busy_timeout = 5000');
        // 老版本 Flutter 库把 tag_galleries 建成了少列版本却标 user_version=12；
        // 这里幂等补列，避免 Tauri 打开时跳过 v12 迁移后找不到 match_mode。
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'tag_galleries'",
        );
        if (tables.isNotEmpty) {
          final columns = await db.rawQuery('PRAGMA table_info(tag_galleries)');
          final hasMatchMode = columns.any(
            (row) => row['name'] == 'match_mode',
          );
          if (!hasMatchMode) {
            await db.execute(
              "ALTER TABLE tag_galleries ADD COLUMN "
              "match_mode TEXT NOT NULL DEFAULT 'all'",
            );
          }
        }
        // 与桌面一致：移除图库要级联清 images
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    _instance = LightConeDb._(db);
    return _instance!;
  }

  /// 当前数据库文件的绝对路径。设置页 / 导出备份 / 桌面端都需要它。
  static Future<String> databasePath() async {
    final String dir;
    if (Platform.isAndroid) {
      dir = await getDatabasesPath();
    } else {
      // Windows/macOS/Linux：放在应用支持目录，绝不写 Program Files。
      final support = await getApplicationSupportDirectory();
      dir = support.path;
    }
    await Directory(dir).create(recursive: true);
    // 演示构建用独立数据库（--dart-define=DEMO_DB=lightcone_demo.db），
    // 正式包永远走 lightcone.db，互不影响。
    const demoDb = String.fromEnvironment('DEMO_DB');
    return p.join(dir, demoDb.isEmpty ? 'lightcone.db' : demoDb);
  }

  /// 关闭连接（导入前要换文件，必须先把句柄放掉）。
  Future<void> close() async {
    _instance = null;
    await database.close();
  }

  /// 校验桌面备份。返回错误描述；null = 可以导入。
  static Future<String?> validateBackup(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) return '文件不存在';
    Database? probe;
    try {
      probe = await openDatabase(sourcePath, readOnly: true);
      final version = Sqflite.firstIntValue(
        await probe.rawQuery('PRAGMA user_version'),
      );
      if (version != 12) {
        return '索引版本 $version 与本应用要求的 12 不一致 —— 请先在桌面端升级';
      }
      final check = await probe.rawQuery('PRAGMA quick_check');
      final ok = check.isNotEmpty && check.first.values.first == 'ok';
      if (!ok) return '文件完整性检查未通过（quick_check）';
      final tables = await probe.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name'] as String? ?? '').toSet();
      final missing = kRequiredTables.where((t) => !names.contains(t)).toList();
      if (missing.isNotEmpty) {
        return '备份缺表：${missing.join('、')}，不是完整的 LightCone 索引';
      }
      return null;
    } catch (e) {
      return '无法打开备份：$e';
    } finally {
      await probe?.close();
    }
  }

  /// 用备份替换当前库。校验由调用方先做（[validateBackup]）。
  /// 返回新的门面实例。
  static Future<LightConeDb> replaceWith(String sourcePath) async {
    final targetPath = await databasePath();
    await _instance?.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$targetPath$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(sourcePath).copy(targetPath);
    _instance = null;
    return open();
  }
}
