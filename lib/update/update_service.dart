import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../pixiv/pixiv_client.dart';

/// 一次「有新版本」的检查结果。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
  });

  /// 远端版本号，已去掉 tag 的 v 前缀（如 1.2.0）。
  final String version;

  /// Release 说明正文，可能为空。
  final String notes;

  final String downloadUrl;
  final String fileName;
  final int sizeBytes;

  String get sizeLabel => sizeBytes <= 0
      ? ''
      : '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 失败原因分类：UI 靠它决定给什么按钮（限流不该显示「去授权」）。
enum UpdateErrorKind { network, rateLimit, install, other }

/// 检查更新失败的原因，交给 UI 决定怎么措辞。
class UpdateException implements Exception {
  const UpdateException(this.message, {this.kind = UpdateErrorKind.other});

  final String message;
  final UpdateErrorKind kind;

  @override
  String toString() => message;
}

/// 应用内更新。
///
/// 分工：版本比对、GitHub 请求、APK 下载都在这里（Dart 有 Dio 和进度回调）；
/// 读版本号、查「安装未知应用」授权、拉起安装器交给原生 UpdateChannel。
///
/// 只能装「同一个签名」的包 —— 换了签名只能卸载重装，这是 Android 的硬规则。
class UpdateService {
  UpdateService._();

  static const _repo = 'AuroraEvelynAria/lightcone-gallery-flutter';

  /// Release 资产的固定文件名。
  ///
  /// 不能带版本号：检查更新走的是 releases/latest 的 302 重定向，只拿得到
  /// tag，拼不出「带版本号的资产名」。固定名还能让下载地址直接指向
  /// /releases/latest/download/...，完全不经过 API。
  static const _assetName = 'lightcone-gallery-android.apk';
  static const _channel = MethodChannel('com.lightcone.gallery/update');

  /// GitHub 匿名访问是 60 次/小时/IP，走代理时出口还是共享 IP。
  /// 所以检查结果在内存里留 10 分钟，免得用户连点几次就把额度耗光。
  static const _cacheTtl = Duration(minutes: 10);

  static UpdateInfo? _cached;
  static DateTime? _cachedAt;

  /// 当前下载的取消句柄。UI 不必 import dio，只需调 [cancelDownload]。
  static CancelToken? _activeCancel;

  /// 当前安装包的版本。原生读 PackageManager，不依赖 pubspec 常量。
  static Future<({String versionName, int versionCode})> appVersion() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('appVersion');
    return (
      versionName: (raw?['versionName'] as String?) ?? '0.0.0',
      versionCode: (raw?['versionCode'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否已被允许安装未知应用。Android 8 以下恒为 true。
  static Future<bool> canInstall() async =>
      (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  /// 跳到本应用的「安装未知应用」授权页。
  static Future<bool> openInstallSettings() async =>
      (await _channel.invokeMethod<bool>('openInstallSettings')) ?? false;

  /// 拉起系统安装器。[path] 必须落在 cache 目录（file_paths.xml 已暴露）。
  static Future<bool> install(String path) async {
    try {
      return (await _channel.invokeMethod<bool>('installApk', {'path': path})) ??
          false;
    } on PlatformException catch (e) {
      throw UpdateException(e.message ?? '拉起安装器失败');
    }
  }

  /// 查最新 release；已是最新版返回 null。
  ///
  /// [proxy] 就是设置里那个 pixiv 代理，原样传进来（回环地址在手机上会被
  /// [PixivClient.normalizeProxy] 判为直连）。
  static Future<UpdateInfo?> check({String? proxy, bool force = false}) async {
    if (!force && _cachedAt != null) {
      final age = DateTime.now().difference(_cachedAt!);
      if (age < _cacheTtl) {
        final hit = _cached;
        if (hit == null) return null;
        final current = await appVersion();
        return _isNewer(hit.version, current.versionName) ? hit : null;
      }
    }

    final dio = _buildDio(proxy);

    // 用 releases/latest 的 302 拿 tag，不碰 API。
    // 匿名 API 是 60 次/小时/IP，国内走代理时出口 IP 常常早被别人用光，
    // 一旦限流整个检查就废了；而 releases 的跳转由 CDN 承担，不限流。
    String? tag;
    try {
      final res = await dio.get<dynamic>(
        'https://github.com/$_repo/releases/latest',
        options: Options(followRedirects: false, validateStatus: (_) => true),
      );
      final location = res.headers.value('location') ?? '';
      final m = RegExp(r'/releases/tag/([^/]+)$').firstMatch(location);
      tag = m?.group(1);
    } on DioException catch (e) {
      throw UpdateException(_networkMessage(e), kind: UpdateErrorKind.network);
    }

    if (tag == null || tag.isEmpty) {
      throw const UpdateException('没有找到已发布的版本');
    }

    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    _cachedAt = DateTime.now();

    final current = await appVersion();
    if (!_isNewer(version, current.versionName)) {
      _cached = null;
      return null;
    }

    final notes = await _fetchNotes(dio, tag);

    _cached = UpdateInfo(
      version: version,
      notes: notes,
      // latest/download 会跳到真正的最新资产，地址不用带版本号。
      downloadUrl:
          'https://github.com/$_repo/releases/latest/download/$_assetName',
      fileName: _assetName,
      sizeBytes: 0,
    );
    return _cached;
  }

  /// 更新说明只有 API 有。拿不到就算了 —— 限流不该连累版本检查。
  static Future<String> _fetchNotes(Dio dio, String tag) async {
    try {
      final res = await dio.get<dynamic>(
        'https://api.github.com/repos/$_repo/releases/tags/$tag',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return ((res.data as Map)['body'] as String?)?.trim() ?? '';
      }
    } catch (_) {
      // 说明拿不到不影响更新本身。
    }
    return '';
  }

  /// 下载 APK 到 cache 目录，返回本地路径。
  ///
  /// 缓存目录正是 file_paths.xml 里暴露给 FileProvider 的那个，
  /// 下载完可以直接交给安装器，不用再挪一次文件。
  static Future<String> download(
    UpdateInfo info, {
    String? proxy,
    void Function(double progress)? onProgress,
  }) async {
    final cancelToken = CancelToken();
    _activeCancel = cancelToken;
    final dir = await getTemporaryDirectory();
    final target = File(p.join(dir.path, info.fileName));

    // 上次下到一半的残留会让用户以为「下好了却装不上」，先清掉。
    if (await target.exists()) await target.delete();

    final dio = _buildDio(proxy);
    try {
      await dio.download(
        info.downloadUrl,
        target.path,
        cancelToken: cancelToken,
        options: Options(headers: {'Accept': 'application/octet-stream'}),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const UpdateException('已取消');
      throw UpdateException(_networkMessage(e));
    }

    _activeCancel = null;
    if (!await target.exists() || await target.length() < 1024) {
      throw const UpdateException('下载的文件不完整');
    }
    return target.path;
  }

  /// 取消正在进行的下载。没有下载时什么都不做。
  static void cancelDownload() {
    _activeCancel?.cancel('user');
    _activeCancel = null;
  }

  /// 清掉缓存目录里下过的旧 APK。
  static Future<void> clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final e in await dir.list().toList()) {
        if (e is File && e.path.endsWith('.apk')) await e.delete();
      }
    } catch (_) {
      // 清缓存失败不影响主流程。
    }
  }

  static Dio _buildDio(String? proxy) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(seconds: 20),
        headers: {'User-Agent': 'LightConeGallery'},
        validateStatus: (_) => true,
      ),
    );
    final resolved = PixivClient.normalizeProxy(proxy);
    if (resolved != null) {
      final hostPort = PixivClient.parseProxyHost(resolved);
      if (hostPort != null) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY ${hostPort.$1}:${hostPort.$2}';
          return client;
        };
      }
    }
    return dio;
  }

  static String _networkMessage(DioException e) {
    final raw = e.message ?? e.type.name;
    if (raw.contains('timed out') ||
        e.type == DioExceptionType.connectionTimeout) {
      return '连接 GitHub 超时，可能需要开代理';
    }
    return '连接失败：$raw';
  }

  /// 远端版本是否比当前新。只比前三段数字，忽略预发布标签。
  static bool _isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .split(RegExp(r'[.+-]'))
        .take(3)
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();

    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
