import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../data/db.dart';
import '../data/repository.dart';
import '../media/media_channel.dart';
import '../pixiv/pixiv_client.dart';

/// 应用级状态：权限、扫描、导入、数据版本。
///
/// 「数据版本」是刷新信号：扫描 / 导入完成后 +1，各屏监听后重拉第一页
/// （Flutter 用 IndexedStack 保活四个 tab，不通知就会显示旧数据 —— 和 Kotlin
/// 版真机撞到的是同一个问题）。
class AppState extends ChangeNotifier {
  AppState(this.repo);

  Repository repo;
  int dataVersion = 0;
  bool hasPermission = false;
  bool permissionAsked = false;
  bool scanning = false;
  String? scanMessage;

  Future<void> ensurePermission() async {
    hasPermission = await MediaChannel.hasPermission();
    notifyListeners();
    if (!hasPermission && !permissionAsked) {
      permissionAsked = true;
      hasPermission = await MediaChannel.requestPermission();
      notifyListeners();
    }
  }

  void bumpData() {
    dataVersion++;
    notifyListeners();
  }

  /// 扫描：一次 MediaStore 枚举，作品库与 pixez 图库同时增量入库。
  Future<String> scanAll() async {
    if (scanning) return '正在扫描，请稍候';
    if (!hasPermission) {
      await ensurePermission();
      if (!hasPermission) return '没有图片权限，无法扫描';
    }
    scanning = true;
    scanMessage = '读取 MediaStore…';
    notifyListeners();
    try {
      final rows = await MediaChannel.listImages();
      scanMessage = '入库（${rows.length} 张）…';
      notifyListeners();
      final artworks = await repo.scanArtworks(rows);
      final library = await repo.ensurePhoneLibrary();
      final gallery = await repo.scanLibrary(library, rows);
      bumpData();
      return '作品库新入库 ${artworks.inserted}（已在库 ${artworks.duplicates}）；'
          '图库新增 ${gallery.inserted}（未变 ${gallery.duplicates}）';
    } catch (e) {
      return '扫描失败：$e';
    } finally {
      scanning = false;
      scanMessage = null;
      notifyListeners();
    }
  }

  /// 导入桌面备份：SAF 选文件 → 校验 → 换库 → 重开。
  Future<String> importBackup() async {
    final path = await MediaChannel.pickBackup();
    if (path == null) return '已取消';
    try {
      final error = await LightConeDb.validateBackup(path);
      if (error != null) return error;
      final newDb = await LightConeDb.replaceWith(path);
      repo = Repository(newDb);
      bumpData();
      return '导入完成';
    } catch (e) {
      return '导入失败：$e';
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// 从桌面备份**只合并元数据**：标题 / 画师 / 标签，不动本机索引。
  /// 比联网抓几千条快得多（桌面已经攒了四千多条）。
  Future<String> importMetadataFromBackup() async {
    final path = await MediaChannel.pickBackup();
    if (path == null) return '已取消';
    try {
      final result = await repo.importMetadataOnly(path);
      bumpData();
      return '已合并：元数据 ${result['total']} 条 · 收藏 ${result['favorites']} 件 · '
          '剩余待补全 ${result['pending']}';
    } catch (e) {
      return '合并元数据失败：$e';
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// 导出备份：WAL 并回主库 → 拷一份临时副本 → 系统文件选择器选保存位置。
  ///
  /// 不用 `VACUUM INTO`：Android 8 的 SQLite 才 3.19，没有那条语法（3.27 才有）。
  Future<String> exportBackup() async {
    final dir = await getDatabasesPath();
    final stamp = DateTime.now();
    final temp = File('$dir/export-${stamp.millisecondsSinceEpoch}.db');
    try {
      await repo.db.execute('PRAGMA wal_checkpoint(FULL)');
      await File(repo.db.path).copy(temp.path);
      final date = '${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}';
      final saved = await MediaChannel.exportBackup(temp.path, 'lightcone-$date.db');
      return saved == null ? '已取消导出' : '已导出（$saved）';
    } catch (e) {
      return '导出失败：$e';
    } finally {
      try {
        await temp.delete();
      } catch (_) {}
    }
  }

  /// 补全元数据：一批接一批跑，直到没有待补全 / 叫停 / 撞限流。
  Future<String> fetchMeta({
    required bool Function() isStopped,
    ValueChanged<MetaBatch>? onBatch,
    void Function(int processed, int total)? onProgress,
  }) async {
    // build 内部会把桌面回环地址规范化为「不走代理」
    final proxy = await repo.setting('pixiv_proxy');
    final dio = PixivClient.build(proxy);
    var done = 0;
    var fetched = 0, failed = 0;
    String? lastError;
    while (!isStopped()) {
      final remaining = await repo.pendingMetaCount();
      if (remaining == 0) break;
      final batch = await PixivClient.fetchBatch(
        repo,
        dio,
        limit: 50,
        overallDone: done,
        watchStop: isStopped,
        onProgress: onProgress,
      );
      done += batch.fetched + batch.missing + batch.failed;
      fetched += batch.fetched;
      failed += batch.failed;
      lastError = batch.lastError ?? lastError;
      onBatch?.call(batch);
      if (batch.aborted) break;
    }
    bumpData();
    return lastError == null
        ? '补全结束：成功 $fetched · 失败 $failed'
        : '补全结束：成功 $fetched · 失败 $failed · $lastError';
  }
}
