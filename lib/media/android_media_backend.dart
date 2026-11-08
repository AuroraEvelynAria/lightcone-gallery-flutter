import 'package:flutter/services.dart';

import '../data/models.dart';
import 'media_backend.dart';

/// Android：沿用 `MediaStoreChannel.kt` 的 MethodChannel 实现。
class AndroidMediaBackend implements MediaBackend {
  static const MethodChannel _channel = MethodChannel(
    'com.lightcone.gallery/media',
  );

  @override
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<MediaImageDto>> listImages({
    String? root,
    Map<String, KnownImageSize>? known,
  }) async {
    final raw = await _channel.invokeMethod<List<Object?>>('listImages');
    if (raw == null) return const [];
    return raw
        .map((item) {
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
        })
        .toList(growable: false);
  }

  @override
  Future<Uint8List?> thumbnail(int id, int size) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {
        'id': id,
        'size': size,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> pickBackup() async =>
      await _channel.invokeMethod<String>('pickBackup');

  @override
  Future<PickedDirectory?> pickDirectory() async {
    final raw = await _channel.invokeMethod<Map>('pickDirectory');
    if (raw == null) return null;
    final map = raw.cast<String, Object?>();
    final path = map['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return PickedDirectory(path, map['name'] as String? ?? '图库');
  }

  @override
  Future<String?> exportBackup(String sourcePath, String name) =>
      _channel.invokeMethod<String>('exportBackup', {
        'source': sourcePath,
        'name': name,
      });

  @override
  Future<bool> shareImages(
    List<String> paths, {
    String? text,
    bool asFile = false,
  }) async {
    if (paths.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('shareImages', {
            'paths': paths,
            'text': text,
            'asFile': asFile,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> saveToGallery(String path, {String? name}) async {
    try {
      return await _channel.invokeMethod<bool>('saveToGallery', {
            'path': path,
            'name': name,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setWallpaper(String path, {String target = 'home'}) async {
    try {
      return await _channel.invokeMethod<bool>('setWallpaper', {
            'path': path,
            'target': target,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> revealInExplorer(List<String> paths) async => false;
}
