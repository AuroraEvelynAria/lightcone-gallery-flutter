import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../pixiv/artist_avatar.dart';

/// 打包好的完整备份（还没落盘到用户选的位置）。
class BackupPack {
  const BackupPack({
    required this.file,
    required this.avatarCount,
    required this.dbBytes,
  });

  final File file;

  /// 打进去的头像文件数（含「这个画师没头像」的 .none 标记）。
  final int avatarCount;
  final int dbBytes;

  String get summary {
    final mb = (dbBytes / 1024 / 1024).toStringAsFixed(1);
    return '数据库 $mb MB · 画师头像 $avatarCount 个';
  }
}

/// 从包里解出来的东西，调用方负责清理 [tempDir]。
class BackupUnpacked {
  const BackupUnpacked({
    required this.dbFile,
    required this.tempDir,
    required this.avatarCount,
  });

  final File dbFile;
  final Directory tempDir;
  final int avatarCount;
}

/// 完整备份包：一个 zip，里面装索引数据库和画师头像缓存。
///
/// 为什么不把头像塞进 SQLite 的 BLOB：头像本身已经是压过的 jpg/webp，
/// 再存成 BLOB 只会让库涨几十兆，而且每次导出都要整表重写一遍。
/// 按文件打进 zip，导入时原样落回 artist_avatars/ 目录。
///
/// 后缀用 .lcbak 而不是 .zip：桌面端的「导入备份」只认裸 .db，
/// 换个后缀能让人一眼看出这包不能直接丢给它。
class BackupBundle {
  BackupBundle._();

  static const extension = 'lcbak';

  static const _dbEntry = 'lightcone.db';
  static const _avatarPrefix = 'artist_avatars/';

  /// zip 的本地文件头，用来区分新包和旧的裸 .db。
  static const _zipMagic = [0x50, 0x4B, 0x03, 0x04];

  static Future<bool> looksLikeZip(File file) async {
    if (!await file.exists()) return false;
    final raf = await file.open();
    try {
      if (await raf.length() < 4) return false;
      final head = await raf.read(4);
      for (var i = 0; i < 4; i++) {
        if (head[i] != _zipMagic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  /// 把 [dbPath] 和当前的头像缓存打成一个 zip，返回临时文件。
  static Future<BackupPack> pack(String dbPath) async {
    final archive = Archive();

    final dbBytes = await File(dbPath).readAsBytes();
    archive.add(ArchiveFile.bytes(_dbEntry, dbBytes));

    var avatars = 0;
    final dir = await ArtistAvatarStore.cacheDirectory();
    if (await dir.exists()) {
      final entries = await dir.list().toList();
      for (final entity in entries) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.isEmpty) continue;
        // .img 是头像；.none 是「这个画师确认没头像」的标记 —— 一起带走，
        // 否则导入后补全器会把同一批人重新去 Pixiv 试一遍。
        archive.add(
          ArchiveFile.bytes(_avatarPrefix + name, await entity.readAsBytes()),
        );
        avatars++;
      }
    }

    final encoded = ZipEncoder().encode(archive);
    final out = await File(
      p.join(
        Directory.systemTemp.path,
        'lightcone-backup-${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    ).writeAsBytes(encoded, flush: true);

    return BackupPack(
      file: out,
      avatarCount: avatars,
      dbBytes: dbBytes.length,
    );
  }

  /// 解开备份包：数据库落到 [tempDir]，头像落到 [tempDir]/artist_avatars。
  static Future<BackupUnpacked> unpack(File bundle) async {
    final bytes = await bundle.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final tempDir = await Directory(
      p.join(
        Directory.systemTemp.path,
        'lightcone-unpack-${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create(recursive: true);

    final avatarDir = Directory(p.join(tempDir.path, 'artist_avatars'));
    File? dbFile;
    var avatars = 0;

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final data = entry.readBytes();
      if (data == null) continue;

      if (entry.name == _dbEntry) {
        dbFile = await File(p.join(tempDir.path, _dbEntry)).writeAsBytes(
          data,
          flush: true,
        );
        continue;
      }
      if (entry.name.startsWith(_avatarPrefix)) {
        final name = p.basename(entry.name);
        if (name.isEmpty) continue;
        if (!await avatarDir.exists()) await avatarDir.create(recursive: true);
        await File(p.join(avatarDir.path, name)).writeAsBytes(data, flush: true);
        avatars++;
      }
    }

    if (dbFile == null) {
      await tempDir.delete(recursive: true);
      throw const FormatException('备份包里没有索引数据库');
    }
    return BackupUnpacked(
      dbFile: dbFile,
      tempDir: tempDir,
      avatarCount: avatars,
    );
  }

  /// 把解出来的头像放进缓存目录，返回实际落盘的数量。
  ///
  /// 只覆盖同名文件、不删别的 —— 用户可能刚在别处补过几个，没必要清空。
  static Future<int> restoreAvatars(Directory avatarDir) async {
    if (!await avatarDir.exists()) return 0;
    final target = await ArtistAvatarStore.cacheDirectory();
    var restored = 0;
    await for (final entity in avatarDir.list()) {
      if (entity is! File) continue;
      await entity.copy(p.join(target.path, p.basename(entity.path)));
      restored++;
    }
    return restored;
  }
}
