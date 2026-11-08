import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/db.dart';
import 'package:lightcone_flutter/data/repository.dart';
import 'package:lightcone_flutter/data/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openDb(String path) {
  return openDatabase(
    path,
    version: 12,
    onCreate: (db, _) async {
      for (final sql in kSchemaV12) {
        await db.execute(sql);
      }
      await db.execute(kMediaIdsTable);
      await db.execute(kIllustAiTable);
    },
  );
}

void main() {
  test('元数据包：导出 → 导入（元数据/标签/AI/收藏评分/画廊）', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('lc-meta-pack-');
    addTearDown(() {
      // FFI 的 SQLite 文件句柄偶尔晚一拍释放，清理失败不影响断言。
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final sourceDb = await _openDb(p.join(dir.path, 'source.db'));
    final source = Repository(LightConeDb.forTesting(sourceDb));
    await sourceDb.insert('illust_meta', {
      'pid': '111',
      'title': '星夜下的鲸鱼娘',
      'artist_uid': '42',
      'artist_name': 'AuroraAria',
      'artist_account': 'auroraaria',
      'page_count': 2,
      'x_restrict': 0,
      'sanity_level': 0,
      'illust_type': 0,
      'create_date': '2026-11-08T00:00:00+00:00',
      'fetched_at': 1,
      'error': null,
      'missing': 0,
    });
    await sourceDb.insert('illust_tags', {'pid': '111', 'tag': '藍'});
    await sourceDb.insert('illust_tags', {'pid': '111', 'tag': 'AI生成'});
    await sourceDb.insert('artists', {
      'uid': '42',
      'name': 'AuroraAria',
      'created_at': 1,
    });
    await sourceDb.insert('illust_ai', {'pid': '111', 'ai_type': 2});
    await sourceDb.insert('images', {
      'library_id': 1,
      'path': r'D:\pixez\111_p0.png',
      'filename': '111_p0.png',
      'extension': 'png',
      'width': 100,
      'height': 150,
      'file_size': 1,
      'modified_at': 1,
      'indexed_at': 1,
      'pid': '111',
      'is_favorite': 1,
      'rating': 4,
    });
    await sourceDb.insert('tag_galleries', {
      'id': 7,
      'name': '蓝色系',
      'tags': '["藍"]',
      'rating': -1,
      'match_mode': 'any',
      'created_at': 1,
    });

    final packPath = p.join(dir.path, 'meta.db');
    await source.exportMetadataPack(packPath);
    expect(File(packPath).existsSync(), isTrue);
    await sourceDb.close();

    final destDb = await _openDb(p.join(dir.path, 'dest.db'));
    final dest = Repository(LightConeDb.forTesting(destDb));
    // 目标端模拟已经扫描过同一件作品：收藏/评分按 pid 合并。
    await destDb.insert('images', {
      'library_id': 1,
      'path': r'D:\pixez\111_p0.png',
      'filename': '111_p0.png',
      'extension': 'png',
      'width': 100,
      'height': 150,
      'file_size': 1,
      'modified_at': 1,
      'indexed_at': 1,
      'pid': '111',
      'is_favorite': 0,
      'rating': 0,
    });
    final result = await dest.importMetadataPack(packPath);
    expect(result['meta'], 1);
    expect(result['tags'], 2);
    expect(result['ai'], 1);
    expect(result['favorites'], 1);
    expect(result['galleries'], 1);

    final meta = await destDb.query(
      'illust_meta',
      where: 'pid = ?',
      whereArgs: ['111'],
    );
    expect(meta.single['title'], '星夜下的鲸鱼娘');
    final tags = await destDb.query(
      'illust_tags',
      where: 'pid = ?',
      whereArgs: ['111'],
    );
    expect(tags.map((t) => t['tag']).toSet(), {'藍', 'AI生成'});
    final ai = await destDb.query(
      'illust_ai',
      where: 'pid = ?',
      whereArgs: ['111'],
    );
    expect(ai.single['ai_type'], 2);
    final favorite = await destDb.query(
      'images',
      where: 'pid = ?',
      whereArgs: ['111'],
    );
    expect(favorite.single['is_favorite'], 1);
    expect(favorite.single['rating'], 4);
    final gallery = await destDb.query(
      'tag_galleries',
      where: 'id = ?',
      whereArgs: [7],
    );
    expect(gallery.single['match_mode'], 'any');

    await destDb.close();
  });
}
