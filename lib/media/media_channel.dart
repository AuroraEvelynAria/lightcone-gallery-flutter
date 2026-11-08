import 'dart:io';
import 'dart:typed_data';

import '../data/models.dart';
import 'android_media_backend.dart';
import 'media_backend.dart';
import 'windows_media_backend.dart';

export 'media_backend.dart' show PickedDirectory;

/// 平台媒体门面：调用方只认识这一层，具体实现按平台切换。
class MediaChannel {
  static final MediaBackend _backend = Platform.isAndroid
      ? AndroidMediaBackend()
      : WindowsMediaBackend();

  static Future<bool> hasPermission() => _backend.hasPermission();

  static Future<bool> requestPermission() => _backend.requestPermission();

  /// Android 枚举全机 MediaStore；Windows 递归扫描 [root]。
  static Future<List<MediaImageDto>> listImages({
    String? root,
    Map<String, KnownImageSize>? known,
  }) => _backend.listImages(root: root, known: known);

  static Future<Uint8List?> thumbnail(int id, int size) =>
      _backend.thumbnail(id, size);

  static Future<String?> pickBackup() => _backend.pickBackup();

  static Future<PickedDirectory?> pickDirectory() => _backend.pickDirectory();

  static Future<String?> exportBackup(String sourcePath, String name) =>
      _backend.exportBackup(sourcePath, name);

  static Future<bool> shareImages(
    List<String> paths, {
    String? text,
    bool asFile = false,
  }) => _backend.shareImages(paths, text: text, asFile: asFile);

  static Future<bool> saveToGallery(String path, {String? name}) =>
      _backend.saveToGallery(path, name: name);

  static Future<bool> setWallpaper(String path, {String target = 'home'}) =>
      _backend.setWallpaper(path, target: target);

  static Future<bool> openUrl(String url) => _backend.openUrl(url);

  static Future<bool> revealInExplorer(List<String> paths) =>
      _backend.revealInExplorer(paths);
}
