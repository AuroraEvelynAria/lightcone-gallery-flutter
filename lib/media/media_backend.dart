import 'dart:typed_data';

import '../data/models.dart';

/// 选出来的图库目录（Android SAF / Windows 文件夹对话框共用）。
class PickedDirectory {
  const PickedDirectory(this.path, this.name);

  final String path;
  final String name;
}

/// 平台媒体后端：Android 走 MediaStore MethodChannel，Windows 走文件系统。
///
/// 调用方只依赖 `MediaChannel` 这层静态门面；具体实现随平台切换。
abstract class MediaBackend {
  Future<bool> hasPermission();

  Future<bool> requestPermission();

  /// 扫描图库目录。Android 返回全机 MediaStore 行（由上层按根过滤）；
  /// Windows 只扫传入的根目录。[known] 是已入库文件的 size/mtime/宽高快照，
  /// Windows 用它跳过没变文件的图片头读取（首扫之后重扫只 stat）。
  Future<List<MediaImageDto>> listImages({
    String? root,
    Map<String, KnownImageSize>? known,
  });

  /// 系统缩略图；Windows MVP 返回 null，让 UI 走 FileImage 解码。
  Future<Uint8List?> thumbnail(int id, int size);

  Future<String?> pickBackup();

  Future<PickedDirectory?> pickDirectory();

  Future<String?> exportBackup(String sourcePath, String name);

  Future<bool> shareImages(
    List<String> paths, {
    String? text,
    bool asFile = false,
  });

  Future<bool> saveToGallery(String path, {String? name});

  Future<bool> setWallpaper(String path, {String target = 'home'});

  Future<bool> openUrl(String url);

  /// Windows 资源管理器定位；Android 暂不支持。
  Future<bool> revealInExplorer(List<String> paths);
}
