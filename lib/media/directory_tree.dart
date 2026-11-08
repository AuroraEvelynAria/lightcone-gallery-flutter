import '../data/models.dart';

/// Android 内部存储的挂载点（MediaStore 的绝对路径前缀）。
const kStorageRoot = '/storage/emulated/0';

/// 把 `/sdcard/...` 之类的别名收敛到 `/storage/emulated/0/...`。
String normalizeStoragePath(String path) {
  if (path == '/sdcard') return kStorageRoot;
  if (path.startsWith('/sdcard/')) {
    return kStorageRoot + path.substring('/sdcard'.length);
  }
  return path;
}

String _parentOf(String path) {
  final slash = path.lastIndexOf('/');
  if (slash <= 0) return path;
  return path.substring(0, slash);
}

String _join(String base, String relative) {
  final rel = relative.replaceAll(RegExp(r'^/+|/+$'), '');
  return rel.isEmpty ? base : '$base/$rel';
}

/// 从 MediaStore 的图片行里整理出的目录树。
///
/// 只包含「有图片的目录」以及它们的祖先 —— 图库目录选择只需要这些。
/// 计数同时给出直接图片数和含子目录的总数，方便用户判断是不是选错了层。
class DirectoryTree {
  DirectoryTree._(this.root, this._direct, this._total);

  final String root;

  /// 目录 → 该目录下直接存放的图片数。
  final Map<String, int> _direct;

  /// 目录 → 该目录及所有子目录的图片总数。
  final Map<String, int> _total;

  final Set<String> _paths = <String>{};

  /// `rows` 是原生 `listImages` 的全量结果；`initialPath` 会被强制收进树里
  /// （即使它现在还是空目录），这样首次启动也能选中默认的 `Pictures/pixez`。
  factory DirectoryTree.fromRows(
    List<MediaImageDto> rows, {
    required String initialPath,
    String root = kStorageRoot,
  }) {
    final direct = <String, int>{};
    final paths = <String>{root};

    for (final row in rows) {
      final path = _join(root, row.relativePath);
      if (!path.startsWith('$root/') && path != root) continue;
      direct[path] = (direct[path] ?? 0) + 1;
      var cursor = path;
      while (cursor != root) {
        paths.add(cursor);
        final parent = _parentOf(cursor);
        if (parent == cursor) break;
        cursor = parent;
      }
      paths.add(root);
    }

    // 初始目录（以及它的祖先）即使没有图片也允许浏览/选中
    var initial = normalizeStoragePath(initialPath);
    if (initial != root && !initial.startsWith('$root/')) initial = root;
    var cursor = initial;
    while (true) {
      paths.add(cursor);
      if (cursor == root) break;
      final parent = _parentOf(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }

    final total = <String, int>{};
    for (final entry in direct.entries) {
      var cursor = entry.key;
      while (true) {
        total[cursor] = (total[cursor] ?? 0) + entry.value;
        if (cursor == root) break;
        final parent = _parentOf(cursor);
        if (parent == cursor) break;
        cursor = parent;
      }
    }

    final tree = DirectoryTree._(root, direct, total);
    tree._paths.addAll(paths);
    return tree;
  }

  static String nameOf(String path) =>
      path == kStorageRoot ? '内部存储' : path.substring(path.lastIndexOf('/') + 1);

  String? parentOf(String path) {
    if (path == root) return null;
    final parent = _parentOf(path);
    return parent == path ? null : parent;
  }

  int directCount(String path) => _direct[path] ?? 0;

  int totalCount(String path) => _total[path] ?? 0;

  bool contains(String path) => _paths.contains(path);

  /// 当前目录的直接子目录，按名字排序。
  List<DirectoryEntry> childrenOf(String path) {
    final entries = <DirectoryEntry>[];
    for (final candidate in _paths) {
      if (candidate == path) continue;
      if (_parentOf(candidate) != path) continue;
      entries.add(
        DirectoryEntry(
          path: candidate,
          directImages: directCount(candidate),
          totalImages: totalCount(candidate),
        ),
      );
    }
    entries.sort((a, b) {
      final byName = nameOf(a.path)
          .toLowerCase()
          .compareTo(nameOf(b.path).toLowerCase());
      return byName != 0 ? byName : a.path.compareTo(b.path);
    });
    return entries;
  }
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.path,
    required this.directImages,
    required this.totalImages,
  });

  final String path;
  final int directImages;
  final int totalImages;
}
