import 'package:flutter/services.dart';

import '../data/models.dart';

/// SAF 选出来的图库目录。
class PickedDirectory {
  const PickedDirectory(this.path, this.name);

  /// 绝对路径前缀，如 `/storage/emulated/0/Pictures/pixez`。
  final String path;
  final String name;
}

/// 与 `MediaStoreChannel.kt` 的桥。枚举与缩略图都在原生侧完成 —— Flutter 只
/// 拿结果，不参与 MediaStore 查询（这是网格流畅的前提）。
class MediaChannel {
  static const MethodChannel _channel = MethodChannel('com.lightcone.gallery/media');

  static Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  static Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  /// 全机图片一次枚举（25k 行约 1 秒，只有扫描时调用）。
  static Future<List<MediaImageDto>> listImages() async {
    final raw = await _channel.invokeMethod<List<Object?>>('listImages');
    if (raw == null) return const [];
    return raw.map((item) {
      final map = (item as Map).cast<String, Object?>();
      return MediaImageDto(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String? ?? '',
        relativePath: map['relativePath'] as String? ?? '',
        size: (map['size'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt() ?? 0,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }

  /// 系统缩略图（MediaProvider 预生成）。失败返回 null，UI 退回文件解码。
  static Future<Uint8List?> thumbnail(int id, int size) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        'thumbnail',
        {'id': id, 'size': size},
      );
    } catch (_) {
      return null;
    }
  }

  /// SAF 选一个 .db 备份：原生侧直接拷进 cache 目录并返回绝对路径。
  static Future<String?> pickBackup() async =>
      await _channel.invokeMethod<String>('pickBackup');

  /// SAF 选图库目录，原生侧把 tree URI 解析成绝对路径。
  static Future<PickedDirectory?> pickDirectory() async {
    final raw = await _channel.invokeMethod<Map>('pickDirectory');
    if (raw == null) return null;
    final map = raw.cast<String, Object?>();
    final path = map['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return PickedDirectory(path, map['name'] as String? ?? '图库');
  }

  /// 导出备份：让用户选保存位置，原生侧把 sourcePath 拷过去。
  /// 返回目标 URI；用户取消返回 null。
  static Future<String?> exportBackup(String sourcePath, String name) =>
      _channel.invokeMethod<String>(
        'exportBackup',
        {'source': sourcePath, 'name': name},
      );

  /// 系统浏览器 / Pixiv App 打开链接（详情页的「在 Pixiv 打开」）。
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
