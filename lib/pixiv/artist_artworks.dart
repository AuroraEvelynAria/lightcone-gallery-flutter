import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/repository.dart';
import 'pixiv_client.dart';

/// 解析 `/ajax/user/{uid}/profile/all`：`illusts` 与 `manga` 两个桶的 key
/// 就是作品 PID（值一般是 null）。插画与漫画都算「作品」——
/// pixez 下载的也是这两类。
///
/// 返回按 PID 降序（新作品在前，和本机瀑布流一致）。
List<String> artworkIdsFromProfile(Object? raw) {
  if (raw is! Map) return const [];
  if (raw['error'] == true) return const [];
  final body = raw['body'];
  if (body is! Map) return const [];
  final ids = <int>{};
  for (final key in const ['illusts', 'manga']) {
    final bucket = body[key];
    if (bucket is! Map) continue;
    for (final id in bucket.keys) {
      final parsed = int.tryParse(id.toString());
      if (parsed != null) ids.add(parsed);
    }
  }
  final sorted = ids.toList()..sort((a, b) => b.compareTo(a));
  return sorted.map((id) => '$id').toList(growable: false);
}

/// 线上作品清单（PID 列表 + 拉取时间）。
class ArtistArtworks {
  const ArtistArtworks({required this.pids, required this.fetchedAt});

  final List<String> pids;
  final DateTime fetchedAt;

  bool isFresh([Duration ttl = ArtistArtworkStore.refreshAfter]) =>
      DateTime.now().difference(fetchedAt) < ttl;
}

/// 画师线上作品清单的缓存：`<appSupport>/artist_artworks/<uid>.json`。
///
/// 只在**画师页第一次打开 / 手动刷新**时拉，不与头像/元数据抢请求；
/// 没网时退回旧缓存（可能过期）或 null，页面照常显示本机部分。
class ArtistArtworkStore {
  static const refreshAfter = Duration(days: 7);
  static const _failureCooldown = Duration(minutes: 2);
  static DateTime? _lastFailure;
  static String? _lastFailureProxy;
  static final _inflight = <String, Future<ArtistArtworks?>>{};
  static Directory? _dir;

  static bool _validUid(String uid) => RegExp(r'^\d+$').hasMatch(uid);

  static Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}artist_artworks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static File _file(Directory dir, String uid) =>
      File('${dir.path}${Platform.pathSeparator}$uid.json');

  /// 只读缓存（不判断新旧）。
  static Future<ArtistArtworks?> cached(String uid) async {
    if (!_validUid(uid)) return null;
    final dir = await _cacheDir();
    final file = _file(dir, uid);
    if (!await file.exists()) return null;
    return _read(file);
  }

  static Future<ArtistArtworks?> _read(File file) async {
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final list = raw['pids'];
      if (list is! List) return null;
      final fetchedAt = raw['fetched_at'];
      return ArtistArtworks(
        pids: [
          for (final pid in list)
            if (pid.toString().isNotEmpty) pid.toString(),
        ],
        fetchedAt: fetchedAt is num
            ? DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt())
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  /// 缓存新鲜就直接用；过期 / 没有才联网（[force] 时无视缓存）。
  static Future<ArtistArtworks?> ensure(
    Repository repo,
    String uid, {
    bool force = false,
  }) async {
    if (!_validUid(uid)) return null;
    final running = _inflight[uid];
    if (running != null) return running;
    final future = _load(repo, uid, force: force);
    _inflight[uid] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(uid);
    }
  }

  static Future<ArtistArtworks?> _load(
    Repository repo,
    String uid, {
    required bool force,
  }) async {
    final dir = await _cacheDir();
    final file = _file(dir, uid);
    final existing = await _read(file);
    if (!force && existing != null && existing.isFresh()) return existing;

    final proxy = await repo.setting('pixiv_proxy');
    final lastFailure = _lastFailure;
    if (!force &&
        lastFailure != null &&
        _lastFailureProxy == proxy &&
        DateTime.now().difference(lastFailure) < _failureCooldown) {
      return existing;
    }

    try {
      final dio = PixivClient.build(proxy);
      dynamic raw;
      // 代理节点偶发掐握手：重试一次（头像下载已经证明这一步有需要）
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await dio.get<dynamic>(
            'https://www.pixiv.net/ajax/user/$uid/profile/all?lang=zh',
          );
          if (response.statusCode == 200) {
            raw = response.data;
            break;
          }
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }
      if (raw == null) return _fail(proxy, existing);
      final decoded = raw is Map<String, dynamic>
          ? raw
          : raw is String
              ? jsonDecode(raw)
              : raw;
      final pids = artworkIdsFromProfile(decoded);
      final now = DateTime.now();
      final result = ArtistArtworks(pids: pids, fetchedAt: now);
      await file.writeAsString(
        jsonEncode({
          'pids': pids,
          'fetched_at': now.millisecondsSinceEpoch,
        }),
        flush: true,
      );
      _lastFailure = null;
      _lastFailureProxy = null;
      return result;
    } catch (_) {
      return _fail(proxy, existing);
    }
  }

  static ArtistArtworks? _fail(String? proxy, ArtistArtworks? existing) {
    _lastFailure = DateTime.now();
    _lastFailureProxy = proxy;
    return existing;
  }
}
