/// 数据模型与解析器：字段语义与桌面端（schema.rs / artworks.rs / artists.rs）
/// 一一对应，解析器的边界用例与那边 Rust 测试互为镜像。
library;

class LibraryRow {
  LibraryRow(this.id, this.path, this.name, this.lastScannedAt);

  final int id;
  final String path;
  final String name;
  final int? lastScannedAt;
}

class ImageRow {
  ImageRow({
    required this.id,
    required this.libraryId,
    required this.path,
    required this.filename,
    required this.fileSize,
    required this.modifiedAt,
    required this.isFavorite,
    required this.rating,
    this.width,
    this.height,
    this.pid,
    this.artistUid,
    this.mediaId,
    this.pageTotal = 1,
    this.xRestrict = 0,
    this.title,
    this.artistName,
    this.artistAccount,
  });

  final int id;
  final int libraryId;
  final String path;
  final String filename;
  final int fileSize;
  final int modifiedAt;
  final bool isFavorite;
  final int rating;
  final int? width;
  final int? height;
  final String? pid;
  final String? artistUid;

  /// MediaStore 行号（本端私有表）。null = 桌面导入的行，缩略图退回文件解码。
  final int? mediaId;

  /// 同一作品的总页数（图库按 PID 归组后由 SQL 带出）；1 = 单页。
  final int pageTotal;

  /// Pixiv 的 R-18 标记（0 = 全年龄）。网格据此决定要不要打码。
  final int xRestrict;

  /// 组内作品的标题 / 画师（illust_meta；没补元数据时为 null）。
  final String? title;
  final String? artistName;
  final String? artistAccount;

  /// 瀑布流每格的高宽比；老行没有宽高时按 3:4 兜底。
  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 0.75;
    return w / h;
  }

  ImageRow copyWith({bool? isFavorite}) => ImageRow(
        id: id,
        libraryId: libraryId,
        path: path,
        filename: filename,
        fileSize: fileSize,
        modifiedAt: modifiedAt,
        isFavorite: isFavorite ?? this.isFavorite,
        rating: rating,
        width: width,
        height: height,
        pid: pid,
        artistUid: artistUid,
        mediaId: mediaId,
        pageTotal: pageTotal,
        xRestrict: xRestrict,
        title: title,
        artistName: artistName,
        artistAccount: artistAccount,
      );
}

class ArtworkRow {
  ArtworkRow({
    required this.id,
    required this.pid,
    required this.originalPath,
    required this.page,
    this.width,
    this.height,
    this.title,
    this.artistName,
    this.artistAccount,
    this.pageCount,
    this.xRestrict,
    this.mediaId,
    this.pageTotal = 1,
    this.favorite = false,
  });

  final int id;
  final String pid;
  final String originalPath;
  final int page;
  final int? width;
  final int? height;
  final String? title;
  final String? artistName;
  final String? artistAccount;
  final int? pageCount;
  final int? xRestrict;
  final int? mediaId;

  /// 本机实际有的页数（网格归组后由 SQL 带出）。用于「N 页」角标。
  final int pageTotal;

  /// 组内任意一页收藏过 = 收藏（卡片上的心）。
  final bool favorite;

  ArtworkRow copyWith({bool? favorite}) => ArtworkRow(
        id: id,
        pid: pid,
        originalPath: originalPath,
        page: page,
        width: width,
        height: height,
        title: title,
        artistName: artistName,
        artistAccount: artistAccount,
        pageCount: pageCount,
        xRestrict: xRestrict,
        mediaId: mediaId,
        pageTotal: pageTotal,
        favorite: favorite ?? this.favorite,
      );

  /// 瀑布流每格的高宽比：老行没有宽高时按 3:4 兜底（桌面同语义）。
  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 0.75;
    return w / h;
  }
}

/// 作品详情页：一个 PID 的元数据、标签与所有页（pixez 详情页同款信息层级）。
class ArtworkDetail {
  ArtworkDetail({
    required this.pid,
    required this.title,
    required this.artistUid,
    required this.artistName,
    required this.artistAccount,
    required this.pageCount,
    required this.xRestrict,
    required this.createDate,
    required this.tags,
    required this.pages,
    required this.favorite,
    this.rating = 0,
    this.savedAt,
  });

  final String pid;
  final String? title;
  final String? artistUid;
  final String? artistName;
  final String? artistAccount;
  final int pageCount;
  final int xRestrict;
  final String? createDate;
  final List<String> tags;
  final List<ArtworkRow> pages;
  final bool favorite;

  /// 整组的评分（0~5，取所有页的最大值）。
  final int rating;

  /// 本地这份文件的保存时间（秒级时间戳，取组内最大 modified_at）。
  /// null = 本机没有对应的 images 行。
  final int? savedAt;

  String get displayTitle =>
      (title?.isNotEmpty ?? false) ? title! : 'PID $pid';

  /// 画师显示名：优先昵称，其次账号名，都没有就只剩 UID。
  String get artistLabel {
    if (artistName?.isNotEmpty ?? false) return artistName!;
    if (artistAccount?.isNotEmpty ?? false) return artistAccount!;
    return artistUid == null ? '未知画师' : 'UID $artistUid';
  }
}

class ArtistCount {  ArtistCount(this.uid, this.name, this.count);

  final String uid;
  final String name;
  final int count;
}

class TagCount {
  TagCount(this.tag, this.count);

  final String tag;
  final int count;
}

/// 画师页头部的汇总（一行 SQL 取完，画师页专用）。
class ArtistProfile {
  ArtistProfile({
    required this.uid,
    required this.name,
    this.account,
    required this.artworks,
    required this.pages,
    required this.favorites,
    required this.bytes,
    this.firstDate,
    this.lastDate,
    this.topTags = const [],
  });

  final String uid;
  final String name;

  /// Pixiv 的 @ 句柄（可能没有）。
  final String? account;

  /// 作品数（按 PID 去重）/ 总页数。
  final int artworks;
  final int pages;

  /// 收藏过的作品数（任一页收藏即算）。
  final int favorites;

  /// 本机这些页的文件总大小。
  final int bytes;

  /// Pixiv 上传日期（`create_date`，取最早 / 最晚）。
  final String? firstDate;
  final String? lastDate;

  /// 该画师作品里出现最多的标签（最多 8 个）。
  final List<String> topTags;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'UID $uid' : trimmed;
  }

  /// `2019-03-21T12:00:00+09:00` → `2019-03-21`。
  String? get firstDay => _day(firstDate);
  String? get lastDay => _day(lastDate);

  static String? _day(String? raw) =>
      (raw != null && raw.length >= 10) ? raw.substring(0, 10) : null;
}

/// 人类可读的文件大小（画师页的「占用」）。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

class TagGalleryRow {
  TagGalleryRow({
    required this.id,
    required this.name,
    required this.tags,
    required this.rating,
    required this.matchMode,
  });

  final int id;
  final String name;
  final List<String> tags;
  final int rating;
  final String matchMode;
}

/// Kotlin 通道返回的一行 MediaStore 数据。
class MediaImageDto {
  MediaImageDto({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.size,
    required this.modified,
    required this.width,
    required this.height,
  });

  final int id;
  final String name;

  /// 已 trim 掉尾斜杠（Kotlin 侧保证）。
  final String relativePath;
  final int size;
  final int modified;
  final int width;
  final int height;

  /// FUSE 直读路径。与 Kotlin 桥同款：相对路径 + 存储根前缀。
  String get path => '/storage/emulated/0/$relativePath/$name';
}

/// 设置页顶部的数据概览（一次查询取完，别在 UI 里连开五条 COUNT）。
class GalleryStats {
  GalleryStats({
    required this.images,
    required this.artworks,
    required this.pages,
    required this.artists,
    required this.tags,
    required this.meta,
    required this.favorites,
    required this.ignored,
  });

  final int images;
  final int artworks;
  final int pages;
  final int artists;
  final int tags;

  /// 成功取到（或确认已删除）的元数据条数。
  final int meta;
  final int favorites;
  final int ignored;
}

class ScanSummary {
  ScanSummary(this.discovered, this.matched, this.inserted, this.duplicates, this.skipped, this.ignored);

  final int discovered;
  final int matched;
  final int inserted;
  final int duplicates;
  final int skipped;
  final int ignored;

  @override
  String toString() =>
      '发现 $discovered · 匹配 $matched · 新入库 $inserted · 已在库 $duplicates · 跳过 $skipped · 忽略 $ignored';
}

/// 解析 `{pid}_p{num}` 命名（容忍完整路径与 `_master1200` 之类后缀）。
/// 与 Rust `parse_pid` 的测试用例逐条对齐。
(String, int)? parsePid(String input) {
  final name = input.split('/').last.split('\\').last;
  final underscore = name.indexOf('_');
  if (underscore <= 0) return null;
  final pid = name.substring(0, underscore);
  if (pid.isEmpty || !pid.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
    return null;
  }
  final rest = name.substring(underscore + 1);
  if (!rest.startsWith('p')) return null;
  final digits = StringBuffer();
  for (final ch in rest.substring(1).codeUnits) {
    if (ch < 0x30 || ch > 0x39) break;
    digits.writeCharCode(ch);
  }
  if (digits.isEmpty) return null;
  final page = int.tryParse(digits.toString());
  if (page == null) return null;
  return (pid, page);
}

/// 从路径反推画师：pixez 落盘目录是 `<画师名>_<画师ID>/<pid>_p<n>`。
/// 与 Rust `parse_artist` 的规则一致（整名数字 / 无 `_` / 名字空都判不出）。
(String uid, String name)? parseArtist(String path) {
  final slash = path.lastIndexOf('/');
  if (slash <= 0) return null;
  var dir = path.substring(0, slash);
  final backslash = dir.lastIndexOf('\\');
  if (backslash >= 0) dir = dir.substring(backslash + 1);
  final slash2 = dir.lastIndexOf('/');
  if (slash2 >= 0) dir = dir.substring(slash2 + 1);

  var digitsStart = dir.length;
  while (digitsStart > 0 &&
      dir.codeUnitAt(digitsStart - 1) >= 0x30 &&
      dir.codeUnitAt(digitsStart - 1) <= 0x39) {
    digitsStart--;
  }
  if (digitsStart == dir.length) return null; // 末尾不是数字
  if (digitsStart == 0) return null; // 整个目录名都是数字
  final head = dir.substring(0, digitsStart);
  if (!head.endsWith('_')) return null;
  final name = head.substring(0, head.length - 1);
  if (name.isEmpty) return null;
  return (dir.substring(digitsStart), name);
}
