import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../data/repository.dart';

/// Pixiv 元数据客户端。走公开的 web ajax 端点（不需要 refresh_token），
/// 限流语义与桌面 `pixiv.rs` / Kotlin 版逐条一致：
/// - 非 200 不重试；429/403 视为限流立刻停；404 视为作品没了（终态）；
/// - 200 里的错误信封要看文案是不是限流词，否则「请求过于频繁」会被记成「已删除」。
class PixivClient {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const requestInterval = Duration(milliseconds: 800);
  static const maxConsecutiveFailures = 3;
  static const cooldownEvery = 200;
  static const cooldown = Duration(seconds: 30);

  static Dio build(String? proxy) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {'User-Agent': _ua, 'Referer': 'https://www.pixiv.net/'},
        validateStatus: (_) => true,
      ),
    );
    final url = normalizeProxy(proxy) ?? '';
    if (url.isNotEmpty) {
      final hostPort = parseProxyHost(url);
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

  /// 桌面端把代理存在 settings 表里，导入备份会原样带过来 —— 但桌面的
  /// `http://127.0.0.1:7897` 在手机上指向手机自己，必然连不通。
  /// 回环地址一律当作「不走代理」（手机若开着 VPN 就能直连）。
  static String? normalizeProxy(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (Platform.isAndroid &&
        (lower.contains('127.0.0.1') ||
            lower.contains('localhost') ||
            lower.contains('[::1]'))) {
      return null;
    }
    return value;
  }

  static (String, int)? parseProxyHost(String url) {
    final rest = url.replaceFirst('http://', '').replaceFirst('https://', '');
    final colon = rest.lastIndexOf(':');
    if (colon <= 0) return (rest, 80);
    final port = int.tryParse(rest.substring(colon + 1));
    if (port == null) return null;
    return (rest.substring(0, colon), port);
  }

  /// 启动自动补全前的轻量探测：4~5 秒连不上 Pixiv 就跳过这一轮，
  /// 避免没开代理/VPN 时每次启动都干等 3 个 20 秒超时。
  static Future<bool> probePixiv(String? proxy) async {
    final dio = build(proxy);
    dio.options.connectTimeout = const Duration(seconds: 4);
    dio.options.receiveTimeout = const Duration(seconds: 5);
    try {
      final response = await dio.get<dynamic>(
        'https://www.pixiv.net/',
        options: Options(responseType: ResponseType.plain),
      );
      return response.statusCode != null;
    } catch (_) {
      return false;
    }
  }

  /// 代理预检失败时自动尝试直连：桌面 Clash 常开 TUN，直连本来就能通，
  /// 而 127.0.0.1:7897 这条 HTTP 代理可能只剩一个坏节点/TLS 握手。
  /// 同一进程内按代理串缓存结果：补头像会连发上千次，不能每次都探两遍。
  static final Map<String, Future<String?>> _proxyResolution = {};

  static Future<String?> resolveProxy(String? raw) {
    final proxy = normalizeProxy(raw);
    if (proxy == null) return Future<String?>.value(null);
    return _proxyResolution.putIfAbsent(proxy, () async {
      if (await probePixiv(proxy)) return proxy;
      if (await probePixiv(null)) return null;
      return proxy;
    });
  }

  /// 代理预检：只做 TCP 握手（2 秒），不发 HTTP —— 20 秒超时前就能判生死。
  static Future<String?> probeProxy(String url) async {
    final hostPort = parseProxyHost(url);
    if (hostPort == null) return '代理地址「$url」格式不对，请填 http://IP:端口';
    try {
      final socket = await Socket.connect(
        hostPort.$1,
        hostPort.$2,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return null;
    } catch (e) {
      return '代理 $url 连不上（$e）：请确认电脑上的代理软件开着、已允许局域网连接，'
          '且手机与电脑在同一网络；手机上开着 VPN 时也可能劫持这条连接';
    }
  }

  static Future<FetchOutcome> fetchIllust(Dio dio, String pid) async {
    if (pid.isEmpty || !pid.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
      return FetchFailed('PID 不是纯数字: $pid');
    }
    // 代理节点偶发掐 TLS 握手（和头像下载同一个毛病），重试一次再判死
    Response<dynamic>? response;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = await dio.get<dynamic>(
          'https://www.pixiv.net/ajax/illust/$pid?lang=zh',
        );
        break;
      } catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    if (response == null) {
      var reason = '请求失败: $lastError';
      final text = '$lastError'.toLowerCase();
      if (text.contains('handshake') || text.contains('connection reset')) {
        reason += ' —— 代理的节点连不上 Pixiv，去代理软件里换一个节点试试';
      }
      return FetchFailed(reason);
    }

    final code = response.statusCode ?? 0;
    if (code == 429 || code == 403) return FetchRateLimited('HTTP $code');
    if (code == 404) return const FetchMissing();
    if (code < 200 || code >= 300) return FetchFailed('HTTP $code');

    final raw = response.data;
    final Map<String, dynamic> json;
    try {
      json = raw is Map<String, dynamic>
          ? raw
          : jsonDecode(raw is String ? raw : jsonEncode(raw))
                as Map<String, dynamic>;
    } catch (e) {
      return FetchFailed('响应不是合法 JSON: $e');
    }

    final parsed = parseIllust(pid, json);
    if (parsed is _Parsed) return FetchFetched(parsed.meta);
    final reason = (parsed as _ParseError).reason;
    final message = json['message']?.toString() ?? '';
    if (looksLikeRateLimit(message) || looksLikeRateLimit(reason)) {
      return FetchRateLimited('接口报错: $message');
    }
    if (json['error'] == true) return const FetchMissing();
    return FetchFailed(reason);
  }

  /// 解析 ajax 响应（字段路径与 Rust `parse_illust` 一致；纯函数便于测试）。
  static Object parseIllust(String pid, Map<String, dynamic> raw) {
    if (raw['error'] == true) {
      return _ParseError('接口报错: ${raw['message'] ?? ''}');
    }
    final body = raw['body'];
    if (body is! Map) return const _ParseError('响应缺少 body 对象');
    String text(String key) => body[key]?.toString() ?? '';
    final title = text('illustTitle').isNotEmpty
        ? text('illustTitle')
        : text('title');
    if (title.isEmpty && text('userId').isEmpty) {
      return const _ParseError('响应里既没有标题也没有画师，形状可能变了');
    }
    final tags = <String>[];
    final tagWrapper = body['tags'];
    if (tagWrapper is Map && tagWrapper['tags'] is List) {
      for (final item in tagWrapper['tags'] as List) {
        if (item is Map &&
            item['tag'] is String &&
            (item['tag'] as String).isNotEmpty) {
          tags.add(item['tag'] as String);
        }
      }
    }
    return _Parsed(
      PixivMeta(
        pid: pid,
        title: title,
        artistUid: text('userId').isEmpty ? null : text('userId'),
        artistName: text('userName').isEmpty ? null : text('userName'),
        artistAccount: text('userAccount').isEmpty ? null : text('userAccount'),
        pageCount: _int(body['pageCount']),
        xRestrict: _int(body['xRestrict']),
        sanityLevel: _int(body['sanityLevel']),
        illustType: _int(body['illustType']),
        createDate: text('createDate').isEmpty ? null : text('createDate'),
        tags: tags,
        aiType: _int(body['illustAIType']),
      ),
    );
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  /// 跨语种限流词。宁可误判成限流（保守，会停下来）也不误判成「已删除」。
  static bool looksLikeRateLimit(String message) {
    final lowered = message.toLowerCase();
    const signals = ['limit', 'rate', 'too many', '频繁', '限制', '制限', '頻度', '暂时'];
    return signals.any(lowered.contains);
  }

  /// 抓一批。`watchStop` 每抓一条检查一次，停止响应才快。
  static Future<MetaBatch> fetchBatch(
    Repository repo,
    Dio dio, {
    int limit = 50,
    int overallDone = 0,
    required bool Function() watchStop,
    void Function(int processed, int total)? onProgress,
  }) async {
    final clamped = limit.clamp(1, 300);
    final proxy = normalizeProxy(await repo.setting('pixiv_proxy')) ?? '';
    if (proxy.isNotEmpty) {
      final error = await probeProxy(proxy);
      if (error != null) return MetaBatch(lastError: error, aborted: true);
    }

    final pids = await repo.pendingPids(clamped);
    if (pids.isEmpty) return MetaBatch();
    var fetched = 0, missing = 0, failed = 0, consecutive = 0;
    String? lastError;
    var aborted = false, rateLimited = false, stopped = false;

    for (var i = 0; i < pids.length; i++) {
      if (watchStop()) {
        stopped = true;
        break;
      }
      final outcome = await fetchIllust(dio, pids[i]);
      switch (outcome) {
        case FetchFetched(:final meta):
          consecutive = 0;
          fetched++;
          await repo.storeMeta(
            {
              'pid': meta.pid,
              'title': meta.title,
              'artist_uid': meta.artistUid,
              'artist_name': meta.artistName,
              'artist_account': meta.artistAccount,
              'page_count': meta.pageCount,
              'x_restrict': meta.xRestrict,
              'sanity_level': meta.sanityLevel,
              'illust_type': meta.illustType,
              'create_date': meta.createDate,
              'fetched_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'error': null,
              'missing': 0,
            },
            meta.tags,
            aiType: meta.aiType,
          );
        case FetchMissing():
          consecutive = 0;
          missing++;
          await repo.markMissing(pids[i]);
        case FetchRateLimited(:final reason):
          rateLimited = true;
          aborted = true;
          failed++;
          lastError = reason;
          await repo.markFailed(pids[i], '被限流，已中止：$reason');
          onProgress?.call(i + 1, pids.length);
          return MetaBatch(
            fetched: fetched,
            missing: missing,
            failed: failed,
            lastError: lastError,
            aborted: true,
            rateLimited: true,
            overallDone: overallDone + i + 1,
          );
        case FetchFailed(:final reason):
          consecutive++;
          failed++;
          lastError = reason;
          await repo.markFailed(pids[i], reason);
          if (consecutive >= maxConsecutiveFailures) {
            aborted = true;
            onProgress?.call(i + 1, pids.length);
            return MetaBatch(
              fetched: fetched,
              missing: missing,
              failed: failed,
              lastError: lastError,
              aborted: true,
              overallDone: overallDone + i + 1,
            );
          }
      }
      onProgress?.call(i + 1, pids.length);
      final soFar = overallDone + i + 1;
      await Future<void>.delayed(
        soFar % cooldownEvery == 0 ? cooldown : requestInterval,
      );
    }
    return MetaBatch(
      fetched: fetched,
      missing: missing,
      failed: failed,
      lastError: lastError,
      aborted: aborted,
      rateLimited: rateLimited,
      stopped: stopped,
      overallDone: overallDone + fetched + missing + failed,
    );
  }
}

class PixivMeta {
  PixivMeta({
    required this.pid,
    required this.title,
    required this.artistUid,
    required this.artistName,
    required this.artistAccount,
    required this.pageCount,
    required this.xRestrict,
    required this.sanityLevel,
    required this.illustType,
    required this.createDate,
    required this.tags,
    this.aiType = 0,
  });

  final String pid;
  final String title;
  final String? artistUid;
  final String? artistName;
  final String? artistAccount;
  final int pageCount;
  final int xRestrict;
  final int sanityLevel;
  final int illustType;
  final String? createDate;
  final List<String> tags;

  /// Pixiv 的 `illustAIType`（2 = AI 生成）。
  final int aiType;
}

sealed class FetchOutcome {
  const FetchOutcome();
}

class FetchFetched extends FetchOutcome {
  const FetchFetched(this.meta);
  final PixivMeta meta;
}

class FetchMissing extends FetchOutcome {
  const FetchMissing();
}

class FetchRateLimited extends FetchOutcome {
  const FetchRateLimited(this.reason);
  final String reason;
}

class FetchFailed extends FetchOutcome {
  const FetchFailed(this.reason);
  final String reason;
}

class MetaBatch {
  MetaBatch({
    this.fetched = 0,
    this.missing = 0,
    this.failed = 0,
    this.lastError,
    this.aborted = false,
    this.rateLimited = false,
    this.stopped = false,
    this.overallDone = 0,
  });

  final int fetched;
  final int missing;
  final int failed;
  final String? lastError;
  final bool aborted;
  final bool rateLimited;
  final bool stopped;
  final int overallDone;
}

class _Parsed {
  const _Parsed(this.meta);
  final PixivMeta meta;
}

class _ParseError {
  const _ParseError(this.reason);
  final String reason;
}
