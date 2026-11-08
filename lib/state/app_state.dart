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

  /// 元数据补全的互斥锁：启动自动补全 / 手动面板不能同时跑。
  bool _metaBusy = false;
  bool get metaBusy => _metaBusy;

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
      final date =
          '${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}';
      final saved = await MediaChannel.exportBackup(
        temp.path,
        'lightcone-$date.db',
      );
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
  /// [maxCount] 用于启动自动补全 —— 只跑一小批，别让用户等一小时。
  Future<String> fetchMeta({
    required bool Function() isStopped,
    ValueChanged<MetaBatch>? onBatch,
    void Function(int processed, int total)? onProgress,
    int? maxCount,
  }) async {
    if (_metaBusy) return '正在补全，请稍候';
    _metaBusy = true;
    try {
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
        if (maxCount != null && done >= maxCount) break;
      }
      bumpData();
      return lastError == null
          ? '补全结束：成功 $fetched · 失败 $failed'
          : '补全结束：成功 $fetched · 失败 $failed · $lastError';
    } finally {
      _metaBusy = false;
    }
  }

  /// 启动时：静默增量扫描当前图库目录，发现缺元数据的新作品就补一小批。
  ///
  /// 返回一条给用户看的轻量提示；null = 没新东西/权限没给/正在手动补全。
  Future<String?> autoSyncOnLaunch({bool enabled = true}) async {
    if (!enabled || _metaBusy) return null;
    await ensurePermission();
    if (!hasPermission) return null;
    await scanAll();
    final pending = await repo.pendingMetaCount();
    if (pending == 0) return null;
    final proxy = await repo.setting('pixiv_proxy');
    if (!await PixivClient.probePixiv(proxy)) {
      return '检测到 $pending 部作品缺元数据，暂时连不上 Pixiv（联网后可手动补全）';
    }
    var fetched = 0;
    await fetchMeta(
      isStopped: () => false,
      maxCount: 50,
      onBatch: (batch) => fetched += batch.fetched,
    );
    final left = await repo.pendingMetaCount();
    if (left == 0) {
      return fetched > 0 ? '已补全 $fetched 部作品' : '缺元数据的作品已处理（已删除 / 无结果）';
    }
    if (fetched == 0) {
      return '检测到 $left 部作品缺元数据，这次没补上（看看代理 / 网络）';
    }
    return '已补全 $fetched 部作品，还有 $left 部下次启动继续';
  }

  /// 回填老作品的 Pixiv AI 标记（`illustAIType`）。
  ///
  /// 只写私有表 `illust_ai`，不动标题/标签；老元数据没有这个字段，
  /// 所以只能逐条打 `/ajax/illust/{pid}`。限流语义与补全元数据一致，
  /// 可停可续：成功/无作品会落行，失败的不落，下次接着补。
  Future<String> fetchAiTypes({
    required bool Function() isStopped,
    void Function(int processed, int total)? onProgress,
  }) async {
    final total = await repo.pendingAiCount();
    if (total == 0) return 'AI 标记已经是全的';
    final proxy = await repo.setting('pixiv_proxy');
    final dio = PixivClient.build(proxy);
    var done = 0, fetched = 0, missing = 0, failed = 0, consecutive = 0;
    var stopped = false;
    String? lastError;
    while (!isStopped()) {
      final pids = await repo.pendingAiPids(50);
      if (pids.isEmpty) break;
      for (var i = 0; i < pids.length; i++) {
        if (isStopped()) {
          stopped = true;
          break;
        }
        final outcome = await PixivClient.fetchIllust(dio, pids[i]);
        var halt = false;
        switch (outcome) {
          case FetchFetched(:final meta):
            await repo.storeAiType(meta.pid, meta.aiType);
            fetched++;
            consecutive = 0;
          case FetchMissing():
            // 作品没了：记 0，别每轮都重试
            await repo.storeAiType(pids[i], 0);
            missing++;
            consecutive = 0;
          case FetchRateLimited(:final reason):
            failed++;
            lastError = reason;
            halt = true;
          case FetchFailed(:final reason):
            failed++;
            lastError = reason;
            consecutive++;
        }
        done++;
        onProgress?.call(done, total);
        if (halt) {
          stopped = true;
          break;
        }
        if (consecutive >= PixivClient.maxConsecutiveFailures) {
          stopped = true;
          break;
        }
        if (i != pids.length - 1) {
          await _stopAwareDelay(
            done % PixivClient.cooldownEvery == 0
                ? PixivClient.cooldown
                : PixivClient.requestInterval,
            isStopped,
          );
        }
      }
      if (stopped) break;
    }
    bumpData();
    final summary = 'AI 标记：成功 $fetched · 无作品 $missing · 失败 $failed';
    final suffix = [
      if (stopped) '已停止',
      ?lastError,
    ].whereType<String>().join(' · ');
    return suffix.isEmpty ? summary : '$summary · $suffix';
  }

  /// 30s 冷却时也能及时响应「停止」。
  Future<void> _stopAwareDelay(
    Duration total,
    bool Function() isStopped,
  ) async {
    var left = total.inMilliseconds;
    while (left > 0) {
      if (isStopped()) return;
      final step = left < 100 ? left : 100;
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
  }
}
