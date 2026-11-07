import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/repository.dart';
import 'pixiv_client.dart';

/// 从 `/ajax/user/{uid}` 的响应里挑头像 URL（纯函数，便于测试）。
///
/// Pixiv 给 `imageBig`（约 500px）和 `image`（约 170px）；优先大图。
/// 只接受 `i.pximg.net` 下的 https 地址 —— 响应是外部数据，不能拿来当
/// 任意 URL 下载器用。
String? avatarUrlFromUser(Object? raw) {
  if (raw is! Map) return null;
  if (raw['error'] == true) return null;
  final body = raw['body'];
  if (body is! Map) return null;
  for (final key in const ['imageBig', 'image']) {
    final value = body[key]?.toString().trim() ?? '';
    if (value.isEmpty) continue;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') continue;
    final host = uri.host.toLowerCase();
    if (host != 'i.pximg.net' && !host.endsWith('.pximg.net')) continue;
    return value;
  }
  return null;
}

/// 同一个地址重试两次（第一次失败后等 250ms）：代理节点偶发掐 TLS 握手时
/// 基本能救回来，不行再由调用方换入口。
Future<Response<T>?> _getWithRetry<T>(
  Dio dio,
  String url, {
  Options? options,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      return await dio.get<T>(url, options: options);
    } catch (_) {
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
  return null;
}

/// 下载候选：先原地址，再用 `i-cf.pximg.net` 的 Cloudflare 入口试一次。
Iterable<String> _candidates(String url) sync* {
  yield url;
  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.toLowerCase() == 'i.pximg.net') {
    yield uri.replace(host: 'i-cf.pximg.net').toString();
  }
}

/// 一次「补画师头像」的结果。
class AvatarSyncResult {
  const AvatarSyncResult({
    required this.total,
    required this.done,
    required this.fetched,
    required this.skipped,
    required this.none,
    required this.failed,
    required this.aborted,
    required this.stopped,
    this.error,
  });

  /// 本次待补（已有头像/已标记没有的都不在里面）。
  final int total;
  final int done;
  final int fetched;

  /// 因为已经有头像文件而跳过的画师数 —— 增量的来源。
  final int skipped;

  /// Pixiv 上确认没有头像（或已删号）的。
  final int none;
  final int failed;
  final bool aborted;
  final bool stopped;
  final String? error;
}

/// 画师头像的本地缓存。
///
/// 两条路径共用同一份缓存（`<appSupport>/artist_avatars/<uid>.img`）：
///
/// - **补全元数据之后批量补**（[syncAll]）：只补没有文件的画师，已有就跳过，
///   随时可停、下次接着补（全增量）；
/// - **打开作品详情时按需补**（[ensure]）：没有文件才联网，超过 30 天再刷新。
///
/// 确认「这个画师没有头像」时写一个 `<uid>.none` 标记，增量时也会跳过，
/// 不会每次都对同一批人重试。
class ArtistAvatarStore {
  static const _refreshAfter = Duration(days: 30);
  static const _maxBytes = 5 * 1024 * 1024;

  /// 详情页按需拉取时的失败冷却：没有代理/断网时别让每个详情页都干等 20 秒。
  static const _failureCooldown = Duration(minutes: 2);
  static DateTime? _lastFailure;
  static String? _lastFailureProxy;
  static final _inflight = <String, Future<File?>>{};
  static Directory? _dir;

  static bool _validUid(String uid) => RegExp(r'^\d+$').hasMatch(uid);

  static Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}artist_avatars');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static File _imageFile(Directory dir, String uid) =>
      File('${dir.path}${Platform.pathSeparator}$uid.img');

  static File _noneMarker(Directory dir, String uid) =>
      File('${dir.path}${Platform.pathSeparator}$uid.none');

  /// 已有头像文件的直接拿来用（不判断新旧）；没有返回 null。
  static Future<File?> cached(String uid) async {
    if (!_validUid(uid)) return null;
    final dir = await _cacheDir();
    final file = _imageFile(dir, uid);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    return stat.size > 0 ? file : null;
  }

  /// 缓存目录里已经处理过的 uid：`.img`（有头像）与 `.none`（确认没有）。
  /// [anyAge] = true 时忽略 30 天 TTL —— 批量补全要的是「有就跳过」。
  static Future<Set<String>> _existingUids({required bool anyAge}) async {
    final dir = await _cacheDir();
    final now = DateTime.now();
    final found = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = name.substring(dot + 1);
      if (ext != 'img' && ext != 'none') continue;
      final uid = name.substring(0, dot);
      if (!_validUid(uid)) continue;
      final stat = await entity.stat();
      if (ext == 'img' && stat.size <= 0) continue;
      if (anyAge || now.difference(stat.modified) < _refreshAfter) {
        found.add(uid);
      }
    }
    return found;
  }

  /// 还有多少画师需要补（批量口径：有文件就算补过）。
  static Future<int> pendingCount(Repository repo) async {
    final uids = await repo.artistUidsWithArtworks();
    if (uids.isEmpty) return 0;
    final existing = await _existingUids(anyAge: true);
    return uids.where((uid) => !existing.contains(uid)).length;
  }

  /// 批量补头像：按作品数从多到少，已有就跳过，可停可续（全增量）。
  ///
  /// 与元数据补全同一套限流：串行 800ms、连续 3 败中止、每 200 个歇 30s。
  static Future<AvatarSyncResult> syncAll(
    Repository repo, {
    required bool Function() watchStop,
    void Function(int done, int total)? onProgress,
  }) async {
    final uids = await repo.artistUidsWithArtworks();
    final existing = await _existingUids(anyAge: true);
    final todo = [
      for (final uid in uids)
        if (!existing.contains(uid)) uid,
    ];
    var done = 0, fetched = 0, none = 0, failed = 0, consecutive = 0;
    var aborted = false, stopped = false;
    String? error;
    for (var i = 0; i < todo.length; i++) {
      if (watchStop()) {
        stopped = true;
        break;
      }
      final file = await ensure(repo, todo[i], batch: true);
      if (file != null) {
        fetched++;
        consecutive = 0;
      } else if (await _hasNoneMarker(todo[i])) {
        none++;
        consecutive = 0; // 「没有头像」也是有效结论，不算失败
      } else {
        failed++;
        consecutive++;
      }
      done = i + 1;
      onProgress?.call(done, todo.length);
      if (consecutive >= PixivClient.maxConsecutiveFailures) {
        aborted = true;
        error = '连续 $consecutive 个画师都失败，已停';
        break;
      }
      if (i != todo.length - 1) {
        await _sleep(
          done % PixivClient.cooldownEvery == 0
              ? PixivClient.cooldown
              : PixivClient.requestInterval,
          watchStop,
        );
      }
    }
    return AvatarSyncResult(
      total: todo.length,
      done: done,
      fetched: fetched,
      skipped: uids.length - todo.length,
      none: none,
      failed: failed,
      aborted: aborted,
      stopped: stopped,
      error: error,
    );
  }

  /// 每 100ms 查一次停止，别让「停止」在 30s 的冷却里干等。
  static Future<void> _sleep(
    Duration total,
    bool Function() watchStop,
  ) async {
    var left = total.inMilliseconds;
    while (left > 0) {
      if (watchStop()) return;
      final step = left < 100 ? left : 100;
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
  }

  static Future<bool> _hasNoneMarker(String uid) async {
    if (!_validUid(uid)) return false;
    final dir = await _cacheDir();
    return _noneMarker(dir, uid).exists();
  }

  /// 先看缓存；没有或过期了才联网。同一 UID 的并发调用共用一个请求。
  /// [batch] = true 时跳过详情页那套失败冷却，由批量逻辑自己判断连续失败。
  static Future<File?> ensure(
    Repository repo,
    String uid, {
    bool batch = false,
  }) async {
    if (!_validUid(uid)) return null;
    final running = _inflight[uid];
    if (running != null) return running;
    final future = _load(repo, uid, batch: batch);
    _inflight[uid] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(uid);
    }
  }

  static Future<File?> _load(
    Repository repo,
    String uid, {
    required bool batch,
  }) async {
    final dir = await _cacheDir();
    final file = _imageFile(dir, uid);
    final marker = _noneMarker(dir, uid);
    final exists = await file.exists();
    if (exists) {
      final stat = await file.stat();
      if (stat.size > 0 && DateTime.now().difference(stat.modified) < _refreshAfter) {
        return file;
      }
    }
    // 已经确认过「这个画师没有头像」：30 天内不再问
    if (await marker.exists()) {
      final stat = await marker.stat();
      if (DateTime.now().difference(stat.modified) < _refreshAfter) return null;
    }

    final proxy = await repo.setting('pixiv_proxy');
    final lastFailure = _lastFailure;
    // 冷却只在同一个代理设置下生效：主人刚填好代理时不能继续挡着
    if (!batch &&
        lastFailure != null &&
        _lastFailureProxy == proxy &&
        DateTime.now().difference(lastFailure) < _failureCooldown) {
      return exists ? file : null;
    }

    /// 联网失败：详情页记下时间做冷却；批量模式交给调用方算连续失败。
    File? fail() {
      if (!batch) {
        _lastFailure = DateTime.now();
        _lastFailureProxy = proxy;
      }
      return exists ? file : null;
    }

    try {
      final dio = PixivClient.build(proxy);
      final response = await _getWithRetry<dynamic>(
        dio,
        'https://www.pixiv.net/ajax/user/$uid?full=1&lang=zh',
      );
      if (response == null || response.statusCode != 200) return fail();
      final raw = response.data;
      final decoded = raw is Map<String, dynamic>
          ? raw
          : raw is String
              ? jsonDecode(raw)
              : raw;
      final url = avatarUrlFromUser(decoded);
      if (url == null) {
        // 接口正常但这个人没有头像：记一笔，增量时直接跳过
        await marker.writeAsString(
          '${DateTime.now().millisecondsSinceEpoch}',
          flush: true,
        );
        return null;
      }

      // 代理节点抽风时 i.pximg.net 的 TLS 握手会直接断 —— 这不恒定，
      // 同一个地址重试一次多半就过；还不行再换 i-cf.pximg.net（同路径的
      // Cloudflare 入口）。
      List<int>? bytes;
      for (final candidate in _candidates(url)) {
        final image = await _getWithRetry<List<int>>(
          dio,
          candidate,
          options: Options(responseType: ResponseType.bytes),
        );
        if (image == null || image.statusCode != 200) continue;
        final contentType =
            image.headers.value(Headers.contentTypeHeader) ?? '';
        final data = image.data;
        if (!contentType.startsWith('image/') ||
            data == null ||
            data.isEmpty ||
            data.length > _maxBytes) {
          continue;
        }
        bytes = data;
        break;
      }
      if (bytes == null) return fail();

      // 先写临时文件再换名，失败时旧头像还在
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
      if (await marker.exists()) await marker.delete();
      _lastFailure = null;
      _lastFailureProxy = null;
      return file;
    } catch (_) {
      return fail();
    }
  }
}
