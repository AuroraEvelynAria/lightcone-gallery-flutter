import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// 数据门面：所有 SQL 都在这里。语义与已在真机验证过的 Kotlin/桌面实现一致。
class Repository {
  Repository(this._db);

  final LightConeDb _db;
  Database get db => _db.database;

  /// 「图库」只扫 pixez 的落盘目录（主人明确要求：不要整个手机相册）。
  /// 作品库本来就是从 `{pid}_p{n}` 命名反推的，天然只包含 pixez 的图。
  static const phonePictures = '/storage/emulated/0/Pictures/pixez';

  /// 上一版的默认根（整个 Pictures）：遇到就迁移/清掉，否则图库会混进 2.5 万张
  /// 截图与表情包。
  static const _legacyPicturesRoot = '/storage/emulated/0/Pictures';

  /// 当前图库根目录。首次启动由用户选（或直接用默认 pixez），之后可在设置里换。
  String _libraryRoot = phonePictures;
  String get libraryRoot => _libraryRoot;

  /// 启动时读一次：设置里的根 → 已有库的路径 → 默认 pixez。
  Future<String> loadLibraryRoot() async {
    final saved = await setting('mobile_library_root');
    if (saved != null && saved.trim().isNotEmpty) {
      _libraryRoot = _normalizeRoot(saved.trim());
      return _libraryRoot;
    }
    final libs = await libraries();
    if (libs.isNotEmpty && libs.first.path.startsWith('/')) {
      _libraryRoot = _normalizeRoot(libs.first.path);
    }
    return _libraryRoot;
  }

  /// 换根：落设置 + 重建/迁移库。旧库会被就地改成新根（收藏/评分保留在新根
  /// 下的文件上），不在新根下的 images 立刻清掉，下次扫描再补齐。
  Future<void> setLibraryRoot(String path, {String? name}) async {
    _libraryRoot = _normalizeRoot(path);
    await setSetting('mobile_library_root', _libraryRoot);
    await ensurePhoneLibrary(name: name);
  }

  static String _normalizeRoot(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// 仅演示构建使用（main.dart 里由 `DEMO_ROOT` 控制）：给演示图补几条假元数据，
  /// 让 README 截图有标题 / 画师 / 标签可看。正常构建永远不会调用。
  Future<void> seedDemoMetadata() async {
    const demos = <(String, String, String, String, List<String>)>[
      ('900001', '深空回响', '10001', 'Aurora', ['原创', '光锥', '少女']),
      ('900002', '海风与旧信', '10002', 'Mira', ['风景', '海']),
      ('900003', '夜航', '10003', 'Nox', ['夜景', '城市', '原创']),
      ('900004', '轨道之外', '10001', 'Aurora', ['原创', '科幻']),
      ('900005', '琥珀时刻', '10004', 'Sol', ['暖色', '插画']),
      ('900006', '薄荷星图', '10002', 'Mira', ['风景', '星星']),
      ('900007', '青苔与铁', '10005', 'Verd', ['绿', '静物']),
      ('900008', '玫瑰星云', '10004', 'Sol', ['星云', '粉']),
      ('900009', '沙丘来信', '10006', 'Dune', ['沙漠', '旅行']),
      ('900010', '深海回廊', '10007', 'Abyss', ['海', '蓝色']),
      ('900011', '极光列车', '10003', 'Nox', ['夜景', '旅行']),
      ('900012', '寄往黎明', '10006', 'Dune', ['清晨', '插画']),
    ];
    for (final demo in demos) {
      final pid = demo.$1;
      final day = (int.parse(pid) % 9) + 1;
      await db.insert(
        'illust_meta',
        {
          'pid': pid,
          'title': demo.$2,
          'artist_uid': demo.$3,
          'artist_name': demo.$4,
          'artist_account': demo.$4.toLowerCase(),
          'page_count': 1,
          'x_restrict': 0,
          'sanity_level': 0,
          'illust_type': 0,
          'create_date': '2026-10-${day.toString().padLeft(2, '0')}T12:00:00+00:00',
          'fetched_at': _now(),
          'error': null,
          'missing': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        'artists',
        {'uid': demo.$3, 'name': demo.$4, 'created_at': _now()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      for (final tag in demo.$5) {
        await db.insert(
          'illust_tags',
          {'pid': pid, 'tag': tag},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// 从另一份 LightCone 索引（桌面端「导出备份」产物）**只合并元数据**：
  /// `illust_meta` / `illust_tags` / `artists.name`，不动本机的 artworks / images。
  ///
  /// 为什么不是整库替换：桌面库的 `original_path` 是 Windows 路径，整库换过来
  /// 手机上的图全都打不开；而元数据是按 PID 挂的，与路径无关，正好可以搬。
  ///
  /// 只搬「成功取到」与「确认已删除」的行 —— 失败行（网络/限流）留在桌面端
  /// 没意义，搬过来还会让待补全数字变小却永远抓不到。
  Future<Map<String, int>> importMetadataOnly(String sourcePath) async {
    final probe = await openDatabase(sourcePath, readOnly: true);
    try {
      final tables = await probe.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
      final names = tables.map((r) => r['name'] as String? ?? '').toSet();
      if (!names.contains('illust_meta') || !names.contains('illust_tags')) {
        throw StateError('不是 LightCone 索引（缺 illust_meta / illust_tags）');
      }
    } finally {
      await probe.close();
    }

    // ATTACH 不能出现在事务里：先挂上，再用事务包住三条合并语句，最后卸载。
    await db.execute('ATTACH DATABASE ? AS src', [sourcePath]);
    try {
      await db.transaction((txn) async {
        await txn.rawInsert(
          'INSERT OR REPLACE INTO illust_meta '
          '(pid, title, artist_uid, artist_name, artist_account, page_count, '
          'x_restrict, sanity_level, illust_type, create_date, fetched_at, error, missing) '
          'SELECT pid, title, artist_uid, artist_name, artist_account, page_count, '
          'x_restrict, sanity_level, illust_type, create_date, fetched_at, error, missing '
          'FROM src.illust_meta WHERE error IS NULL OR missing = 1',
        );
        await txn.rawInsert(
          'INSERT OR IGNORE INTO illust_tags (pid, tag) '
          'SELECT pid, tag FROM src.illust_tags '
          'WHERE pid IN (SELECT pid FROM artworks)',
        );
        await txn.rawUpdate(
          'UPDATE artists SET name = '
          '(SELECT s.name FROM src.artists s WHERE s.uid = artists.uid) '
          'WHERE EXISTS (SELECT 1 FROM src.artists s WHERE s.uid = artists.uid)',
        );
        // 标签画廊（桌面存的组合）：手机端只读，点进去按标签筛
        await txn.rawInsert(
          'INSERT OR REPLACE INTO tag_galleries (id, name, tags, rating, created_at) '
          'SELECT id, name, tags, rating, created_at FROM src.tag_galleries',
        );
        // 收藏 / 评分按 PID 合并（桌面的路径是 Windows 的，不能按 path 对）：
        // 手机端是整组状态，取桌面组内最大值。
        await txn.rawUpdate(
          'UPDATE images SET is_favorite = 1 WHERE pid IS NOT NULL AND EXISTS ('
          'SELECT 1 FROM src.images s WHERE s.pid = images.pid AND s.is_favorite = 1)',
        );
        await txn.rawUpdate(
          'UPDATE images SET rating = '
          '(SELECT MAX(s.rating) FROM src.images s WHERE s.pid = images.pid) '
          'WHERE pid IS NOT NULL AND EXISTS ('
          'SELECT 1 FROM src.images s WHERE s.pid = images.pid AND s.rating > 0)',
        );
      });
    } finally {
      await db.execute('DETACH DATABASE src');
    }

    final total = (await db.rawQuery('SELECT COUNT(*) c FROM illust_meta')).first['c'] as int? ?? 0;
    final favorites = (await db.rawQuery(
      'SELECT COUNT(DISTINCT pid) c FROM images WHERE is_favorite = 1',
    ))
        .first['c'] as int? ??
        0;
    final pending = await pendingMetaCount();
    return {'total': total, 'pending': pending, 'favorites': favorites};
  }

  // ---------------------------------------------------------------- 图库

  Future<List<LibraryRow>> libraries() async {
    final rows = await db.query('libraries', orderBy: 'id');
    return rows
        .map((r) => LibraryRow(
              r['id'] as int,
              r['path'] as String,
              r['name'] as String,
              r['last_scanned_at'] as int?,
            ))
        .toList();
  }

  /// 确保当前图库根存在；顺手把旧版「整个 Pictures」的库迁过来/删掉。
  ///
  /// 迁移而不是重建：保留旧库里根下的行（收藏/评分不丢），下一次 `scanLibrary`
  /// 的差集会把不在新根下的行删干净。
  Future<LibraryRow> ensurePhoneLibrary({String? name}) async {
    final root = _libraryRoot;
    final libName = name ?? (root.split('/').last.isEmpty ? '图库' : root.split('/').last);
    // 作品库与图库同口径：只收根目录下的文件。这里清掉历史遗留（别处目录
    // 下载的 pixiv 命名文件）；Windows 路径的桌面导入行不动 —— 那是等重新
    // 扫描时按 (pid,page) 更新掉的。
    await db.delete(
      'artworks',
      where: "original_path LIKE '/storage/%' AND original_path NOT LIKE ?",
      whereArgs: ['$root/%'],
    );
    final existing = await db.query(
      'libraries',
      where: 'path = ?',
      whereArgs: [root],
    );
    final legacy = await db.query(
      'libraries',
      where: 'path = ?',
      whereArgs: [_legacyPicturesRoot],
    );

    if (existing.isNotEmpty) {
      // 新根已在：旧版整 Pictures 的库没有存在意义
      if (legacy.isNotEmpty && legacy.first['id'] != existing.first['id']) {
        await db.delete('libraries', where: 'id = ?', whereArgs: [legacy.first['id']]);
      }
      final r = existing.first;
      return LibraryRow(r['id'] as int, r['path'] as String, r['name'] as String, r['last_scanned_at'] as int?);
    }
    if (legacy.isNotEmpty) {
      final r = legacy.first;
      final id = r['id'] as int;
      await db.update(
        'libraries',
        {'path': root, 'name': libName},
        where: 'id = ?',
        whereArgs: [id],
      );
      // 立刻清掉不在新根下的行：否则要等下一次扫描的差集，图库里还挂着
      // 两万张截图/表情包。
      await db.delete(
        'images',
        where: 'library_id = ? AND path NOT LIKE ?',
        whereArgs: [id, '$root/%'],
      );
      return LibraryRow(id, root, libName, r['last_scanned_at'] as int?);
    }
    final now = _now();
    final id = await db.insert('libraries', {
      'path': root,
      'name': libName,
      'created_at': now,
    });
    return LibraryRow(id, root, libName, null);
  }

  /// 图库分页。**按作品（PID）归组**：同一作品的 51 页只出现一张卡，
  /// 卡面是封面页，点进去才是竖排长图 / 单张查看（pixez 的语义）。
  ///
  /// 归组用子查询算出每组的封面（MIN(id)）、页数、收藏状态与最新时间，
  /// 再 join 回 images 拿封面行 —— 比在 SELECT 里堆窗口函数更好读。
  ///
  /// 注意 WHERE 只在有条件时才拼 —— 空条件拼出 `WHERE  ORDER BY` 是 Kotlin 版
  /// 真机上撞过的 SQL 语法错误，这里同一处坑不再踩。
  Future<List<ImageRow>> imagesPage({
    int? libraryId,
    bool favoriteOnly = false,
    int minRating = 0,
    bool descending = true,
    required int offset,
    required int limit,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (libraryId != null) {
      clauses.add('i.library_id = ?');
      args.add(libraryId);
    }
    // 收藏是整组的状态：任意一页收藏过，封面就带心
    if (favoriteOnly) clauses.add('g.fav = 1');
    if (minRating > 0) {
      clauses.add('i.rating >= ?');
      args.add(minRating);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')} ';
    final order = descending ? 'DESC' : 'ASC';
    args.addAll([limit, offset]);
    final rows = await db.rawQuery(
      'SELECT i.*, m.media_id AS media_id, g.n AS page_total, g.fav AS group_fav, '
      'COALESCE(meta.x_restrict, 0) AS x_restrict '
      'FROM images i '
      'JOIN ('
      '  SELECT COALESCE(pid, \'#\' || id) AS k, MIN(id) AS cover_id, '
      '         COUNT(*) AS n, MAX(is_favorite) AS fav, MAX(modified_at) AS last_modified '
      '  FROM images GROUP BY k'
      ') g ON g.cover_id = i.id '
      'LEFT JOIN media_ids m ON m.path = i.path '
      'LEFT JOIN illust_meta meta ON meta.pid = i.pid '
      '$where'
      'ORDER BY g.last_modified $order, i.id $order LIMIT ? OFFSET ?',
      args,
    );
    return rows.map(_imageRow).toList();
  }

  Future<int> imageCount({int? libraryId}) async {
    final result = libraryId == null
        ? await db.rawQuery('SELECT COUNT(*) c FROM images')
        : await db.rawQuery('SELECT COUNT(*) c FROM images WHERE library_id = ?', [libraryId]);
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> setFavorite(int imageId, bool favorite) => db.update(
        'images',
        {'is_favorite': favorite ? 1 : 0},
        where: 'id = ?',
        whereArgs: [imageId],
      );

  Future<void> setRating(int imageId, int rating) => db.update(
        'images',
        {'rating': rating},
        where: 'id = ?',
        whereArgs: [imageId],
      );

  // ---------------------------------------------------------------- 作品库

  /// 作品分页：**一个 PID 一行**（封面 = 最小页），多页作品只占一张卡。
  Future<List<ArtworkRow>> artworksPage({
    String? artistUid,
    List<String> tags = const [],
    int xRestrict = -1,
    bool favoriteOnly = false,
    required int offset,
    required int limit,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (artistUid != null) {
      clauses.add('a.artist_uid = ?');
      args.add(artistUid);
    }
    for (final tag in tags) {
      clauses.add('a.pid IN (SELECT pid FROM illust_tags WHERE tag = ?)');
      args.add(tag);
    }
    if (xRestrict >= 0) {
      clauses.add('COALESCE(meta.x_restrict, 0) = ?');
      args.add(xRestrict);
    }
    if (favoriteOnly) {
      // 收藏是整组的状态：任意一页收藏过就算
      clauses.add(
        'EXISTS (SELECT 1 FROM images im WHERE im.pid = a.pid AND im.is_favorite = 1)',
      );
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')} ';
    args.addAll([limit, offset]);
    final rows = await db.rawQuery(
      'SELECT a.*, meta.title AS title, meta.artist_name AS artist_name, '
      'meta.artist_account AS artist_account, meta.page_count AS page_count, '
      'meta.x_restrict AS x_restrict, m.media_id AS media_id, '
      '(SELECT COUNT(*) FROM artworks a2 WHERE a2.pid = a.pid) AS page_total '
      'FROM artworks a '
      'JOIN (SELECT pid, MIN(page) AS page FROM artworks GROUP BY pid) cover '
      '  ON cover.pid = a.pid AND cover.page = a.page '
      'LEFT JOIN illust_meta meta ON meta.pid = a.pid '
      'LEFT JOIN media_ids m ON m.path = a.original_path '
      '$where'
      'ORDER BY CAST(a.pid AS INTEGER) DESC LIMIT ? OFFSET ?',
      args,
    );
    return rows.map(_artworkRow).toList();
  }

  Future<ArtworkRow?> artworkById(int id) async {
    final rows = await db.rawQuery(
      'SELECT a.*, meta.title AS title, meta.artist_name AS artist_name, '
      'meta.artist_account AS artist_account, meta.page_count AS page_count, '
      'meta.x_restrict AS x_restrict, m.media_id AS media_id '
      'FROM artworks a LEFT JOIN illust_meta meta ON meta.pid = a.pid '
      'LEFT JOIN media_ids m ON m.path = a.original_path WHERE a.id = ?',
      [id],
    );
    return rows.isEmpty ? null : _artworkRow(rows.first);
  }

  /// 同一 PID 的所有页（详情页的 PageView 用），按页码排序。
  Future<List<ArtworkRow>> artworksForPid(String pid) async {
    final rows = await db.rawQuery(
      'SELECT a.*, meta.title AS title, meta.artist_name AS artist_name, '
      'meta.artist_account AS artist_account, meta.page_count AS page_count, '
      'meta.x_restrict AS x_restrict, m.media_id AS media_id '
      'FROM artworks a LEFT JOIN illust_meta meta ON meta.pid = a.pid '
      'LEFT JOIN media_ids m ON m.path = a.original_path '
      'WHERE a.pid = ? ORDER BY a.page',
      [pid],
    );
    return rows.map(_artworkRow).toList();
  }

  /// 收藏是按图片行存的（与桌面一致）：一个 PID 的所有页一起翻。
  Future<bool> isPidFavorite(String pid) async {
    final rows = await db.rawQuery(
      'SELECT MAX(is_favorite) AS f FROM images WHERE pid = ?',
      [pid],
    );
    return ((rows.first['f'] as int?) ?? 0) == 1;
  }

  /// 返回受影响的行数：0 = 这个 PID 不在 pixez 图库里（收藏只对图库图片生效）。
  Future<int> setPidFavorite(String pid, bool favorite) => db.update(
        'images',
        {'is_favorite': favorite ? 1 : 0},
        where: 'pid = ?',
        whereArgs: [pid],
      );

  /// 多选收藏：一次更新多个 PID 的所有页。
  Future<int> setPidsFavorite(List<String> pids, bool favorite) async {
    if (pids.isEmpty) return 0;
    final marks = List.filled(pids.length, '?').join(',');
    return db.update(
      'images',
      {'is_favorite': favorite ? 1 : 0},
      where: 'pid IN ($marks)',
      whereArgs: pids,
    );
  }

  /// 评分也是整组：一个作品的所有页同一分。
  Future<int> setPidRating(String pid, int rating) => db.update(
        'images',
        {'rating': rating},
        where: 'pid = ?',
        whereArgs: [pid],
      );

  /// 详情页的一次性装载：元数据 + 标签 + 所有页 + 收藏/评分状态。
  Future<ArtworkDetail> artworkDetail(String pid) async {
    final metaRows = await db.query('illust_meta', where: 'pid = ?', whereArgs: [pid]);
    final tagRows = await db.query(
      'illust_tags',
      where: 'pid = ?',
      whereArgs: [pid],
      orderBy: 'tag',
    );
    final pages = await artworksForPid(pid);
    final favorite = await isPidFavorite(pid);
    final ratingRows = await db.rawQuery(
      'SELECT MAX(rating) AS r FROM images WHERE pid = ?',
      [pid],
    );
    final savedRows = await db.rawQuery(
      'SELECT MAX(modified_at) AS saved FROM images WHERE pid = ?',
      [pid],
    );
    final meta = metaRows.isEmpty ? null : metaRows.first;
    return ArtworkDetail(
      pid: pid,
      title: meta?['title'] as String?,
      artistUid: meta?['artist_uid'] as String?,
      artistName: meta?['artist_name'] as String?,
      artistAccount: meta?['artist_account'] as String?,
      pageCount: (meta?['page_count'] as int?) ?? pages.length,
      xRestrict: (meta?['x_restrict'] as int?) ?? 0,
      createDate: meta?['create_date'] as String?,
      tags: tagRows.map((r) => r['tag'] as String).toList(growable: false),
      pages: pages,
      favorite: favorite,
      rating: (ratingRows.first['r'] as int?) ?? 0,
      savedAt: (savedRows.first['saved'] as int?) ?? 0,
    );
  }

  Future<int> artworkCount() async {    final result = await db.rawQuery('SELECT COUNT(*) c FROM artworks');
    return (result.first['c'] as int?) ?? 0;
  }

  /// 画师维度计数。**默认不截断**：`cnt DESC` 走聚合，6k 作品/1.5k 画师毫秒级；
  /// 之前写死 LIMIT 500 会让分类页永远只显示 500 条（主人真机发现的）。
  Future<List<ArtistCount>> artistCounts({int? limit}) async {
    final rows = await db.rawQuery(
      'SELECT a.artist_uid AS uid, ar.name AS name, COUNT(*) AS cnt '
      'FROM artworks a JOIN artists ar ON ar.uid = a.artist_uid '
      'WHERE a.artist_uid IS NOT NULL '
      'GROUP BY a.artist_uid ORDER BY cnt DESC'
      '${limit == null ? '' : ' LIMIT ?'}',
      limit == null ? const [] : [limit],
    );
    return rows
        .map((r) => ArtistCount(r['uid'] as String, r['name'] as String? ?? '', r['cnt'] as int))
        .toList();
  }

  /// 画师页头部的汇总：一条 SQL 取完计数 / 占用 / 日期，标签再一条。
  Future<ArtistProfile> artistProfile(String uid) async {
    final row = (await db.rawQuery(
      'SELECT '
      '(SELECT COUNT(DISTINCT a.pid) FROM artworks a WHERE a.artist_uid = ?) AS artworks, '
      '(SELECT COUNT(*) FROM artworks a WHERE a.artist_uid = ?) AS pages, '
      '(SELECT COUNT(DISTINCT im.pid) FROM images im '
      '  JOIN artworks a ON a.pid = im.pid '
      '  WHERE a.artist_uid = ? AND im.is_favorite = 1) AS favorites, '
      '(SELECT COALESCE(SUM(im.file_size), 0) FROM images im '
      '  JOIN artworks a ON a.pid = im.pid WHERE a.artist_uid = ?) AS bytes, '
      '(SELECT MIN(m.create_date) FROM illust_meta m '
      '  JOIN artworks a ON a.pid = m.pid WHERE a.artist_uid = ?) AS first_date, '
      '(SELECT MAX(m.create_date) FROM illust_meta m '
      '  JOIN artworks a ON a.pid = m.pid WHERE a.artist_uid = ?) AS last_date, '
      '(SELECT name FROM artists WHERE uid = ?) AS artist_name, '
      '(SELECT artist_name FROM illust_meta WHERE artist_uid = ? '
      '  AND artist_name IS NOT NULL AND artist_name != "" LIMIT 1) AS meta_name, '
      '(SELECT artist_account FROM illust_meta WHERE artist_uid = ? '
      '  AND artist_account IS NOT NULL AND artist_account != "" LIMIT 1) AS meta_account',
      [uid, uid, uid, uid, uid, uid, uid, uid, uid],
    ))
        .first;
    final tags = await db.rawQuery(
      'SELECT tag, COUNT(*) c FROM illust_tags '
      'WHERE pid IN (SELECT pid FROM artworks WHERE artist_uid = ?) '
      'GROUP BY tag ORDER BY c DESC LIMIT 8',
      [uid],
    );
    String? text(String key) {
      final value = (row[key] as String?)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    return ArtistProfile(
      uid: uid,
      name: text('artist_name') ?? text('meta_name') ?? '',
      account: text('meta_account'),
      artworks: (row['artworks'] as int?) ?? 0,
      pages: (row['pages'] as int?) ?? 0,
      favorites: (row['favorites'] as int?) ?? 0,
      bytes: (row['bytes'] as num?)?.toInt() ?? 0,
      firstDate: text('first_date'),
      lastDate: text('last_date'),
      topTags: tags.map((r) => r['tag'] as String).toList(),
    );
  }

  /// 这批 PID 里本机已有的是哪些（画师页比对线上清单用）。
  /// 分块查询：SQLite 的变量上限是 999，线上画师可能有几千个作品。
  Future<Set<String>> existingPids(Iterable<String> pids) async {
    final all = pids.toList(growable: false);
    final found = <String>{};
    for (var start = 0; start < all.length; start += 500) {
      final chunk = all.sublist(start, (start + 500).clamp(0, all.length));
      if (chunk.isEmpty) continue;
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT DISTINCT pid FROM artworks WHERE pid IN ($placeholders)',
        chunk,
      );
      found.addAll(rows.map((r) => r['pid'] as String));
    }
    return found;
  }

  /// 有作品的画师 uid，按作品数从多到少 —— 补头像时先补作品多的画师，
  /// 中途停止也不亏。补头像用（头像文件在应用目录里，不在库里）。
  Future<List<String>> artistUidsWithArtworks() async {
    final rows = await db.rawQuery(
      'SELECT artist_uid, COUNT(*) c FROM artworks '
      'WHERE artist_uid IS NOT NULL AND artist_uid != "" '
      'GROUP BY artist_uid ORDER BY c DESC',
    );
    return rows.map((r) => r['artist_uid'] as String).toList();
  }

  /// 标签维度计数。同样不截断：31k 行 illust_tags 的 GROUP BY 有 idx_illust_tags_tag
  /// 撑着，手机上也只要几十毫秒。
  Future<List<TagCount>> tagCounts({int? limit}) async {
    final rows = await db.rawQuery(
      'SELECT tag, COUNT(*) AS cnt FROM illust_tags GROUP BY tag ORDER BY cnt DESC'
      '${limit == null ? '' : ' LIMIT ?'}',
      limit == null ? const [] : [limit],
    );
    return rows.map((r) => TagCount(r['tag'] as String, r['cnt'] as int)).toList();
  }

  /// 移出作品库：删行 + 记忽略名单（重扫不再收回），语义同桌面 remove_artworks。
  Future<void> removeArtworks(List<int> ids) async {
    if (ids.isEmpty) return;
    final now = _now();
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('artworks', columns: ['pid', 'page'], where: 'id = ?', whereArgs: [id]);
        if (rows.isEmpty) continue;
        await txn.insert(
          'ignored_artworks',
          {'pid': rows.first['pid'], 'page': rows.first['page'], 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.delete('artworks', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<int> ignoredCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) c FROM ignored_artworks');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearIgnored() => db.delete('ignored_artworks');

  /// 桌面端保存的标签画廊（tag_galleries）：手机端只读，点进去用标签筛作品。
  Future<List<TagGalleryRow>> tagGalleries() async {
    final rows = await db.query('tag_galleries', orderBy: 'id');
    return rows.map((r) {
      List<String> tags = const [];
      try {
        final raw = jsonDecode((r['tags'] as String?) ?? '[]');
        if (raw is List) tags = raw.map((e) => '$e').toList(growable: false);
      } catch (_) {
        // 桌面写入的是 JSON 数组；解析失败就当空画廊，不影响其他条目
      }
      return TagGalleryRow(
        id: r['id'] as int,
        name: r['name'] as String,
        tags: tags,
        rating: (r['rating'] as int?) ?? -1,
        matchMode: (r['match_mode'] as String?) ?? 'all',
      );
    }).toList();
  }

  // ---------------------------------------------------------------- 检索

  static String _escapeLike(String q) =>
      q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');

  Future<List<ArtworkRow>> searchArtworks(String query, {int limit = 100}) async {
    final like = '%${_escapeLike(query.trim())}%';
    final rows = await db.rawQuery(
      "SELECT a.*, meta.title AS title, meta.artist_name AS artist_name, "
      "meta.artist_account AS artist_account, meta.page_count AS page_count, "
      "meta.x_restrict AS x_restrict, m.media_id AS media_id, "
      "(SELECT COUNT(*) FROM artworks a2 WHERE a2.pid = a.pid) AS page_total "
      "FROM artworks a "
      "JOIN (SELECT pid, MIN(page) AS page FROM artworks GROUP BY pid) cover "
      "  ON cover.pid = a.pid AND cover.page = a.page "
      "LEFT JOIN illust_meta meta ON meta.pid = a.pid "
      "LEFT JOIN media_ids m ON m.path = a.original_path "
      "WHERE a.pid LIKE ?1 ESCAPE '\\' "
      "OR meta.title LIKE ?1 ESCAPE '\\' "
      "OR meta.artist_name LIKE ?1 ESCAPE '\\' "
      "OR EXISTS (SELECT 1 FROM illust_tags it WHERE it.pid = a.pid AND it.tag LIKE ?1 ESCAPE '\\') "
      "ORDER BY CAST(a.pid AS INTEGER) DESC LIMIT ?2",
      [like, limit],
    );
    return rows.map(_artworkRow).toList();
  }

  Future<List<ImageRow>> searchImages(String query, {int limit = 100}) async {
    final like = '%${_escapeLike(query.trim())}%';
    // 按 PID 归组：搜到「各种各样娅」时只出一张卡，而不是 51 页
    final rows = await db.rawQuery(
      "SELECT i.*, m.media_id AS media_id, g.n AS page_total, g.fav AS group_fav, "
      "COALESCE(meta.x_restrict, 0) AS x_restrict "
      "FROM images i "
      "JOIN ("
      "  SELECT COALESCE(pid, '#' || id) AS k, MIN(id) AS cover_id, "
      "         COUNT(*) AS n, MAX(is_favorite) AS fav "
      "  FROM images WHERE filename LIKE ?1 ESCAPE '\\' GROUP BY k"
      ") g ON g.cover_id = i.id "
      "LEFT JOIN media_ids m ON m.path = i.path "
      "LEFT JOIN illust_meta meta ON meta.pid = i.pid "
      "ORDER BY i.modified_at DESC, i.id DESC LIMIT ?2",
      [like, limit],
    );
    return rows.map(_imageRow).toList();
  }

  // ---------------------------------------------------------------- 扫描

  /// 作品库：MediaStore 行 → (pid,page) 去重 + 忽略名单 + 画师路径反推。
  /// 语义与桌面 `scan_media_rows` / Kotlin 版完全一致（保留先入者）。
  Future<ScanSummary> scanArtworks(List<MediaImageDto> rows) async {
    final now = _now();
    final knownRows = await db.query('artworks', columns: ['pid', 'page', 'original_path']);
    final knownPaths = <String, String>{
      for (final r in knownRows)
        '${r['pid']}:${r['page']}': (r['original_path'] as String?) ?? '',
    };
    final ignoredRows = await db.query('ignored_artworks', columns: ['pid', 'page']);
    final ignored = ignoredRows.map((r) => '${r['pid']}:${r['page']}').toSet();

    var matched = 0;
    var duplicates = 0;
    var ignoredCount = 0;
    final seen = <String>{};
    final artistRows = <Map<String, Object?>>[];
    final artworkRows = <Map<String, Object?>>[];
    final pathUpdates = <Map<String, Object?>>[];
    final roots = <String>{};

    for (final row in rows) {
      // 作品库与图库同口径：只认当前根目录下的文件。
      if (!row.path.startsWith('$_libraryRoot/')) continue;
      final parsed = parsePid(row.name);
      if (parsed == null) continue;
      matched++;
      final (pid, page) = parsed;
      final key = '$pid:$page';
      final slash = row.path.lastIndexOf('/');
      if (slash > 0) roots.add(row.path.substring(0, slash));
      if (ignored.contains(key)) {
        ignoredCount++;
        continue;
      }
      if (seen.contains(key)) {
        duplicates++;
        continue;
      }
      final knownPath = knownPaths[key];
      if (knownPath != null) {
        seen.add(key);
        duplicates++;
        // 同一页换了路径：桌面导入后重扫会走到这里，把 Windows 路径换成
        // 手机上的真实路径（否则详情页永远打不开图）。
        if (knownPath != row.path) {
          pathUpdates.add({
            'pid': pid,
            'page': page,
            'original_path': row.path,
            'width': row.width > 0 ? row.width : null,
            'height': row.height > 0 ? row.height : null,
            'artist_uid': parseArtist(row.path)?.$1,
          });
        }
        continue;
      }
      seen.add(key);
      final artist = parseArtist(row.path);
      if (artist != null) {
        artistRows.add({
          'uid': artist.$1,
          'name': artist.$2,
          'created_at': now,
        });
      }
      artworkRows.add({
        'pid': pid,
        'original_path': row.path,
        'thumbnail_path': null,
        'page': page,
        'created_at': now,
        'artist_uid': artist?.$1,
        'width': row.width > 0 ? row.width : null,
        'height': row.height > 0 ? row.height : null,
      });
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final artist in artistRows) {
        batch.insert('artists', artist, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final artwork in artworkRows) {
        batch.insert('artworks', artwork, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final update in pathUpdates) {
        batch.update(
          'artworks',
          {
            'original_path': update['original_path'],
            'width': update['width'],
            'height': update['height'],
            'artist_uid': update['artist_uid'],
          },
          where: 'pid = ? AND page = ?',
          whereArgs: [update['pid'], update['page']],
        );
      }
      for (final root in roots) {
        batch.insert('artwork_roots', {'path': root, 'created_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      // 路径反推不出画师时，用元数据里的 artist_uid 兜底（演示图 / 用户改过目录名）
      await txn.rawUpdate(
        'UPDATE artworks SET artist_uid = '
        '(SELECT m.artist_uid FROM illust_meta m WHERE m.pid = artworks.pid) '
        'WHERE artist_uid IS NULL AND EXISTS ('
        'SELECT 1 FROM illust_meta m WHERE m.pid = artworks.pid AND m.artist_uid IS NOT NULL)',
      );
      // 缩略图映射：一次扫描顺带把全机 path→id 更新到最新
      for (final row in rows) {
        batch.insert('media_ids', {'path': row.path, 'media_id': row.id},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    return ScanSummary(rows.length, matched, artworkRows.length, duplicates, rows.length - matched, ignoredCount);
  }

  /// 通用图库：按库根过滤 + (path,size,mtime) 增量 + 差集删除。
  Future<ScanSummary> scanLibrary(LibraryRow library, List<MediaImageDto> allRows) async {
    if (!library.path.startsWith('/')) {
      // 桌面导入的库是 Windows 路径，手机上不存在 —— 跳过不报错
      return ScanSummary(0, 0, 0, 0, 0, 0);
    }
    final root = library.path.endsWith('/')
        ? library.path.substring(0, library.path.length - 1)
        : library.path;
    final rows = allRows.where((r) => r.path.startsWith('$root/')).toList();
    if (rows.isEmpty) return ScanSummary(0, 0, 0, 0, 0, 0);

    final now = _now();
    final snapshotRows = await db.query(
      'images',
      columns: ['id', 'path', 'file_size', 'modified_at'],
      where: 'library_id = ?',
      whereArgs: [library.id],
    );
    final snapshot = {
      for (final r in snapshotRows) r['path'] as String: r,
    };

    final newRows = <Map<String, Object?>>[];
    final updates = <Map<String, Object?>>[];
    final seen = <String>{};
    var unchanged = 0;

    for (final row in rows) {
      seen.add(row.path);
      final extension = row.name.contains('.') ? row.name.split('.').last.toLowerCase() : '';
      final existing = snapshot[row.path];
      final artist = parseArtist(row.path);
      if (existing == null) {
        newRows.add({
          'library_id': library.id,
          'path': row.path,
          'filename': row.name,
          'extension': extension,
          'width': row.width > 0 ? row.width : null,
          'height': row.height > 0 ? row.height : null,
          'file_size': row.size,
          'modified_at': row.modified,
          'taken_at': null,
          'is_favorite': 0,
          'rating': 0,
          'indexed_at': now,
          'artist_uid': artist?.$1,
          'pid': parsePid(row.name)?.$1,
        });
      } else if (existing['file_size'] != row.size || existing['modified_at'] != row.modified) {
        updates.add({
          'id': existing['id'],
          'width': row.width > 0 ? row.width : null,
          'height': row.height > 0 ? row.height : null,
          'file_size': row.size,
          'modified_at': row.modified,
        });
      } else {
        unchanged++;
      }
    }
    final removed = snapshot.keys.where((path) => !seen.contains(path)).toList();

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in newRows) {
        batch.insert('images', row, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final update in updates) {
        final id = update['id'];
        batch.update(
          'images',
          {
            'width': update['width'],
            'height': update['height'],
            'file_size': update['file_size'],
            'modified_at': update['modified_at'],
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      for (final path in removed) {
        batch.delete('images', where: 'library_id = ? AND path = ?', whereArgs: [library.id, path]);
      }
      for (final row in rows) {
        batch.insert('media_ids', {'path': row.path, 'media_id': row.id},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      batch.update('libraries', {'last_scanned_at': now}, where: 'id = ?', whereArgs: [library.id]);
      await batch.commit(noResult: true);
    });

    return ScanSummary(
      rows.length,
      rows.length,
      newRows.length,
      unchanged,
      0,
      0,
    );
  }

  // ---------------------------------------------------------------- 元数据

  Future<int> pendingMetaCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) c FROM artworks a WHERE NOT EXISTS ('
      'SELECT 1 FROM illust_meta m WHERE m.pid = a.pid AND (m.error IS NULL OR m.missing = 1))',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<String>> pendingPids(int limit) async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT pid FROM artworks a WHERE NOT EXISTS ('
      'SELECT 1 FROM illust_meta m WHERE m.pid = a.pid AND (m.error IS NULL OR m.missing = 1)) '
      'ORDER BY CAST(pid AS INTEGER) DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['pid'] as String).toList();
  }

  /// 设置页的数据概览：一条 SQL 取全部计数。
  Future<GalleryStats> stats() async {
    final row = (await db.rawQuery(
      'SELECT '
      '(SELECT COUNT(*) FROM images) AS images, '
      '(SELECT COUNT(DISTINCT pid) FROM artworks) AS artworks, '
      '(SELECT COUNT(*) FROM artworks) AS pages, '
      '(SELECT COUNT(*) FROM artists) AS artists, '
      '(SELECT COUNT(*) FROM illust_tags) AS tags, '
      "(SELECT COUNT(*) FROM illust_meta WHERE error IS NULL OR missing = 1) AS meta, "
      '(SELECT COUNT(DISTINCT pid) FROM images WHERE is_favorite = 1) AS favorites, '      '(SELECT COUNT(*) FROM ignored_artworks) AS ignored',
    ))
        .first;
    int read(String key) => (row[key] as int?) ?? 0;
    return GalleryStats(
      images: read('images'),
      artworks: read('artworks'),
      pages: read('pages'),
      artists: read('artists'),
      tags: read('tags'),
      meta: read('meta'),
      favorites: read('favorites'),
      ignored: read('ignored'),
    );
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> storeMeta(Map<String, Object?> meta, List<String> tags) async {
    await db.transaction((txn) async {
      await txn.insert('illust_meta', meta, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('illust_tags', where: 'pid = ?', whereArgs: [meta['pid']]);
      final batch = txn.batch();
      for (final tag in tags) {
        batch.insert('illust_tags', {'pid': meta['pid'], 'tag': tag},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final uid = meta['artist_uid'] as String?;
      final name = meta['artist_name'] as String?;
      if (uid != null && name != null) {
        batch.update('artists', {'name': name}, where: 'uid = ?', whereArgs: [uid]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> markMissing(String pid) async {
    await db.transaction((txn) async {
      await txn.delete('illust_tags', where: 'pid = ?', whereArgs: [pid]);
      await txn.insert(
        'illust_meta',
        {
          'pid': pid,
          'title': '',
          'page_count': 0,
          'x_restrict': 0,
          'sanity_level': 0,
          'illust_type': 0,
          'fetched_at': _now(),
          'error': null,
          'missing': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> markFailed(String pid, String reason) => db.insert(
        'illust_meta',
        {
          'pid': pid,
          'title': '',
          'page_count': 0,
          'x_restrict': 0,
          'sanity_level': 0,
          'illust_type': 0,
          'fetched_at': _now(),
          'error': reason,
          'missing': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---------------------------------------------------------------- 映射

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  ImageRow _imageRow(Map<String, Object?> r) => ImageRow(
        id: r['id'] as int,
        libraryId: r['library_id'] as int,
        path: r['path'] as String,
        filename: r['filename'] as String,
        fileSize: (r['file_size'] as int?) ?? 0,
        modifiedAt: (r['modified_at'] as int?) ?? 0,
        isFavorite: ((r['group_fav'] ?? r['is_favorite']) as int?) == 1,
        rating: (r['rating'] as int?) ?? 0,
        width: r['width'] as int?,
        height: r['height'] as int?,
        pid: r['pid'] as String?,
        artistUid: r['artist_uid'] as String?,
        mediaId: r['media_id'] as int?,
        pageTotal: (r['page_total'] as int?) ?? 1,
        xRestrict: (r['x_restrict'] as int?) ?? 0,
      );

  ArtworkRow _artworkRow(Map<String, Object?> r) => ArtworkRow(
        id: r['id'] as int,
        pid: r['pid'] as String,
        originalPath: r['original_path'] as String,
        page: (r['page'] as int?) ?? 0,
        width: r['width'] as int?,
        height: r['height'] as int?,
        title: r['title'] as String?,
        artistName: r['artist_name'] as String?,
        artistAccount: r['artist_account'] as String?,
        pageCount: r['page_count'] as int?,
        xRestrict: r['x_restrict'] as int?,
        mediaId: r['media_id'] as int?,
        pageTotal: (r['page_total'] as int?) ?? 1,
      );
}
