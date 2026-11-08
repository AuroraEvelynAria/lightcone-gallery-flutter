import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import 'media_backend.dart';

const _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.tif',
  '.tiff',
  '.ico',
};

const _skippedDirs = {
  '.git',
  '.svn',
  '.hg',
  'node_modules',
  'target',
  r'$RECYCLE.BIN',
  'System Volume Information',
  '__pycache__',
};

/// Windows：没有 MediaStore，直接递归扫文件系统。
class WindowsMediaBackend implements MediaBackend {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<MediaImageDto>> listImages({
    String? root,
    Map<String, KnownImageSize>? known,
  }) async {
    final dir = root?.trim() ?? '';
    if (dir.isEmpty || !await Directory(dir).exists()) return const [];
    try {
      // 大目录递归 + 读文件头放到 isolate，别卡住 UI。
      return await Isolate.run(() => _scanDirectory(dir, known));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Uint8List?> thumbnail(int id, int size) async => null;

  @override
  Future<String?> pickBackup() async {
    const typeGroup = XTypeGroup(label: 'LightCone 索引', extensions: ['db']);
    // 默认跳到 Tauri 的 app_data_dir，少点几次目录。
    String? initialDirectory;
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      final tauriDir = p.join(appData, 'com.lightcone.gallery');
      if (await Directory(tauriDir).exists()) initialDirectory = tauriDir;
    }
    final picked = await openFile(
      acceptedTypeGroups: const [typeGroup],
      initialDirectory: initialDirectory,
    );
    if (picked == null) return null;
    final tempDir = await getTemporaryDirectory();
    final temp = File(
      p.join(
        tempDir.path,
        'lightcone-import-${DateTime.now().millisecondsSinceEpoch}.db',
      ),
    );
    // 上层导入后会删除返回路径：必须给临时副本，不能删用户原文件。
    await File(picked.path).copy(temp.path);
    return temp.path;
  }

  @override
  Future<PickedDirectory?> pickDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '选择文件夹');
    if (path == null || path.isEmpty) return null;
    return PickedDirectory(path, p.basename(path));
  }

  @override
  Future<String?> exportBackup(String sourcePath, String name) async {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'LightCone 索引', extensions: ['db']),
      ],
    );
    if (location == null) return null;
    await File(sourcePath).copy(location.path);
    return location.path;
  }

  @override
  Future<bool> shareImages(
    List<String> paths, {
    String? text,
    bool asFile = false,
  }) => revealInExplorer(paths);

  @override
  Future<bool> saveToGallery(String path, {String? name}) async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return false;
    final dir = Directory(p.join(home, 'Pictures', 'LightCone'));
    await dir.create(recursive: true);
    final source = File(path);
    if (!await source.exists()) return false;
    final baseName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : p.basename(path);
    var target = File(p.join(dir.path, baseName));
    var index = 1;
    while (await target.exists()) {
      final stem = p.basenameWithoutExtension(baseName);
      final ext = p.extension(baseName);
      target = File(p.join(dir.path, '$stem (${index++})$ext'));
    }
    await source.copy(target.path);
    return true;
  }

  @override
  Future<bool> setWallpaper(String path, {String target = 'home'}) async =>
      false;

  @override
  Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> revealInExplorer(List<String> paths) async {
    if (paths.isEmpty) return false;
    try {
      final target = p.normalize(paths.first);
      await Process.run('explorer.exe', ['/select,$target']);
      return true;
    } catch (_) {
      return false;
    }
  }
}

List<MediaImageDto> _scanDirectory(
  String root,
  Map<String, KnownImageSize>? known,
) {
  final rootDir = Directory(root);
  final results = <MediaImageDto>[];
  try {
    for (final entity in rootDir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root);
      final segments = p.split(relative);
      if (segments.any(
        (segment) => segment.startsWith('.') || _skippedDirs.contains(segment),
      )) {
        continue;
      }
      final extension = p.extension(entity.path).toLowerCase();
      if (!_imageExtensions.contains(extension)) continue;
      final normalized = p.normalize(entity.path);

      var size = 0;
      var modified = 0;
      try {
        final stat = entity.statSync();
        size = stat.size;
        modified = stat.modified.millisecondsSinceEpoch ~/ 1000;
      } catch (_) {}

      var width = 0;
      var height = 0;
      final hint = known?[normalized];
      if (hint != null &&
          hint.size == size &&
          hint.modified == modified &&
          hint.width > 0 &&
          hint.height > 0) {
        // 文件没变：直接用库里已有的宽高，跳过图片头读取。
        width = hint.width;
        height = hint.height;
      } else {
        try {
          final got = ImageSizeGetter.getSizeResult(FileInput(entity));
          width = got.size.width.round();
          height = got.size.height.round();
        } on UnsupportedError {
          // 不认识的格式：仍然入图库，只是瀑布流退回默认比例。
        } catch (_) {}
      }

      results.add(
        MediaImageDto(
          id: 0,
          name: p.basename(entity.path),
          relativePath: p.dirname(relative),
          size: size,
          modified: modified,
          width: width,
          height: height,
          absolutePath: normalized,
        ),
      );
    }
  } catch (_) {
    // 根目录不可读：返回已经扫到的部分。
  }
  results.sort((a, b) => a.path.compareTo(b.path));
  return results;
}
