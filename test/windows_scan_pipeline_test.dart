import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/db.dart';
import 'package:lightcone_flutter/data/models.dart';
import 'package:lightcone_flutter/data/repository.dart';
import 'package:lightcone_flutter/data/schema.dart';
import 'package:lightcone_flutter/media/windows_media_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Windows 扫描 → 作品库/图库入库（不写 media_ids）', () async {
    if (!Platform.isWindows) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final temp = Directory.systemTemp.createTempSync('lc-pipeline-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final lib = Directory('${temp.path}\\pixez\\AuroraAria_71934453')
      ..createSync(recursive: true);
    final icon = File(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    );
    icon.copySync('${lib.path}\\151827235_p0.png');
    icon.copySync('${lib.path}\\151827235_p1.png');

    final dbDir = Directory('${temp.path}\\db')..createSync();
    final db = await openDatabase(
      '${dbDir.path}\\test.db',
      version: 12,
      onCreate: (db, _) async {
        for (final sql in kSchemaV12) {
          await db.execute(sql);
        }
        await db.execute(kMediaIdsTable);
        await db.execute(kIllustAiTable);
      },
    );
    addTearDown(db.close);

    final repo = Repository(LightConeDb.forTesting(db));
    await repo.setLibraryRoot('${temp.path}\\pixez', name: 'pixez');
    final rows = await WindowsMediaBackend().listImages(root: repo.libraryRoot);
    expect(rows.length, 2);
    expect(parseArtist(rows.first.path), ('71934453', 'AuroraAria'));

    final artworks = await repo.scanArtworks(rows);
    final library = await repo.ensurePhoneLibrary();
    final gallery = await repo.scanLibrary(library, rows);
    expect(artworks.inserted, 2);
    expect(gallery.inserted, 2);
    expect(await db.query('media_ids'), isEmpty);

    final stats = await repo.stats();
    expect(stats.images, 2);
    expect(stats.artworks, 1);
    expect(stats.pages, 2);

    final images = await repo.imagesPage(offset: 0, limit: 10);
    expect(images.length, 1);
    expect(images.first.pid, '151827235');
    final works = await repo.artworksPage(offset: 0, limit: 10);
    expect(works.length, 1);
    expect(works.first.pid, '151827235');
    expect(works.first.pageTotal, 2);

    // FFI 的 SQLite 默认关闭双引号字符串兼容：这两个查询过去用 `!= ""`，
    // 在 Windows 上会报 no such column: ""，补全面板因此卡在「统计中…」。
    final artistUids = await repo.artistUidsWithArtworks();
    expect(artistUids, contains('71934453'));
    final profile = await repo.artistProfile('71934453');
    expect(profile, isNotNull);
    expect(profile.artworks, greaterThan(0));
  });
}
