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

Future<void> _insertImage(
  Database db, {
  required int libraryId,
  required String path,
  required String pid,
  int favorite = 0,
  int rating = 0,
}) {
  return db.insert('images', {
    'library_id': libraryId,
    'path': path,
    'filename': p.basename(path),
    'extension': 'png',
    'width': 100,
    'height': 150,
    'file_size': 1,
    'modified_at': 1,
    'indexed_at': 1,
    'pid': pid,
    'is_favorite': favorite,
    'rating': rating,
  });
}

void main() {
  test('整库导入：新 PID 补入，旧 PID 不降级，AI/画师/评分取并集', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('lc-meta-import-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final destDb = await _openDb(p.join(dir.path, 'dest.db'));
    final dest = Repository(LightConeDb.forTesting(destDb));
    await destDb.insert('libraries', {
      'id': 1,
      'path': r'D:\pixez',
      'name': 'pixez',
      'created_at': 1,
    });
    for (final pid in ['1', '2', '3', '4']) {
      await destDb.insert('artworks', {
        'pid': pid,
        'original_path': 'D:/pixez/${pid}_p0.png',
        'page': 0,
        'created_at': 1,
      });
    }
    await _insertImage(
      destDb,
      libraryId: 1,
      path: r'D:\pixez\1_p0.png',
      pid: '1',
      rating: 5,
    );
    await _insertImage(
      destDb,
      libraryId: 1,
      path: r'D:\pixez\2_p0.png',
      pid: '2',
    );

    // 本机已有：1 比来源新，3 比来源旧，4 是本机失败行。
    await destDb.insert('illust_meta', {
      'pid': '1',
      'title': 'dest newer',
      'fetched_at': 200,
      'page_count': 1,
    });
    await destDb.insert('illust_meta', {
      'pid': '3',
      'title': 'dest older',
      'fetched_at': 100,
      'page_count': 1,
    });
    await destDb.insert('illust_meta', {
      'pid': '4',
      'title': 'dest failed',
      'fetched_at': 300,
      'error': 'timeout',
      'page_count': 1,
    });
    await destDb.insert('artists', {
      'uid': '42',
      'name': 'OldName',
      'created_at': 1,
    });
    await destDb.insert('illust_ai', {'pid': '1', 'ai_type': 0});
    await destDb.insert('illust_ai', {'pid': '3', 'ai_type': 2});

    final sourceDb = await _openDb(p.join(dir.path, 'source.db'));
    await sourceDb.insert('illust_meta', {
      'pid': '1',
      'title': 'source older',
      'fetched_at': 100,
      'page_count': 1,
    });
    await sourceDb.insert('illust_meta', {
      'pid': '2',
      'title': 'source new pid',
      'fetched_at': 100,
      'page_count': 1,
    });
    await sourceDb.insert('illust_meta', {
      'pid': '3',
      'title': 'source newer',
      'fetched_at': 300,
      'page_count': 1,
    });
    await sourceDb.insert('illust_meta', {
      'pid': '4',
      'title': 'source recovery',
      'fetched_at': 50,
      'page_count': 1,
    });
    await sourceDb.insert('illust_meta', {
      'pid': '6',
      'title': 'failed source',
      'fetched_at': 999,
      'error': 'network',
      'page_count': 1,
    });
    for (final row in [
      {'pid': '1', 'tag': 'a'},
      {'pid': '2', 'tag': 'b'},
      {'pid': '6', 'tag': 'c'},
    ]) {
      await sourceDb.insert('illust_tags', row);
    }
    await sourceDb.insert('artists', {
      'uid': '42',
      'name': 'NewName',
      'created_at': 1,
    });
    await sourceDb.insert('artists', {
      'uid': '43',
      'name': 'Fresh',
      'created_at': 1,
    });
    await sourceDb.insert('illust_ai', {'pid': '1', 'ai_type': 2});
    await sourceDb.insert('illust_ai', {'pid': '2', 'ai_type': 0});
    await sourceDb.insert('illust_ai', {'pid': '3', 'ai_type': 0});
    await sourceDb.insert('images', {
      'library_id': 1,
      'path': '/phone/1_p0.png',
      'filename': '1_p0.png',
      'extension': 'png',
      'width': 100,
      'height': 150,
      'file_size': 1,
      'modified_at': 1,
      'indexed_at': 1,
      'pid': '1',
      'is_favorite': 1,
      'rating': 3,
    });
    await sourceDb.insert('images', {
      'library_id': 1,
      'path': '/phone/2_p0.png',
      'filename': '2_p0.png',
      'extension': 'png',
      'width': 100,
      'height': 150,
      'file_size': 1,
      'modified_at': 1,
      'indexed_at': 1,
      'pid': '2',
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
    await sourceDb.close();

    final result = await dest.importMetadataOnly(p.join(dir.path, 'source.db'));
    expect(result['total'], 4);
    expect(result['favorites'], 1);

    final meta = await destDb.query('illust_meta', orderBy: 'pid');
    final byPid = {for (final row in meta) row['pid']: row};
    expect(byPid.keys, containsAll(['1', '2', '3', '4']));
    expect(byPid.containsKey('6'), isFalse);
    expect(byPid['1']!['title'], 'dest newer');
    expect(byPid['1']!['fetched_at'], 200);
    expect(byPid['2']!['title'], 'source new pid');
    expect(byPid['3']!['title'], 'source newer');
    expect(byPid['4']!['title'], 'source recovery');

    final tags = await destDb.query('illust_tags');
    expect(tags.map((r) => r['tag']).toSet(), {'a', 'b', 'c'});

    final artists = await destDb.query('artists', orderBy: 'uid');
    expect(artists.firstWhere((r) => r['uid'] == '42')['name'], 'NewName');
    expect(artists.firstWhere((r) => r['uid'] == '43')['name'], 'Fresh');

    final ai = await destDb.query('illust_ai', orderBy: 'pid');
    final aiByPid = {for (final row in ai) row['pid']: row['ai_type']};
    expect(aiByPid['1'], 2);
    expect(aiByPid['2'], 0);
    expect(aiByPid['3'], 2); // 本机已是 2，不被来源的 0 降级

    final images = await destDb.query('images', orderBy: 'pid');
    final imageByPid = {for (final row in images) row['pid']: row};
    expect(imageByPid['1']!['is_favorite'], 1);
    expect(imageByPid['1']!['rating'], 5); // 取两边最大值
    expect(imageByPid['2']!['rating'], 4);

    final gallery = await destDb.query(
      'tag_galleries',
      where: 'id = ?',
      whereArgs: [7],
    );
    expect(gallery.single['match_mode'], 'any');
    await destDb.close();
  });

  test('整库导入：来源没有 illust_ai 也不报错（Tauri v11 兼容）', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('lc-meta-import-v11-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final sourceDb = await openDatabase(
      p.join(dir.path, 'source.db'),
      version: 11,
      onCreate: (db, _) async {
        for (final sql in kSchemaV12) {
          if (sql.contains('illust_ai')) continue;
          await db.execute(sql);
        }
        await db.execute(kMediaIdsTable);
      },
    );
    await sourceDb.insert('illust_meta', {
      'pid': '9',
      'title': 'v11',
      'fetched_at': 1,
      'page_count': 1,
    });
    await sourceDb.insert('illust_tags', {'pid': '9', 'tag': 'x'});
    await sourceDb.close();

    final destDb = await _openDb(p.join(dir.path, 'dest.db'));
    final dest = Repository(LightConeDb.forTesting(destDb));
    final result = await dest.importMetadataOnly(p.join(dir.path, 'source.db'));
    expect(result['total'], 1);
    final tags = await destDb.query('illust_tags');
    expect(tags.single['tag'], 'x');
    await destDb.close();
  });
}
