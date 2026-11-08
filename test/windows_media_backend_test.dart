import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';
import 'package:lightcone_flutter/data/schema.dart';
import 'package:lightcone_flutter/media/windows_media_backend.dart';

void main() {
  test('schema v12 的 tag_galleries 带 match_mode（与 Tauri 对齐）', () {
    final sql = kSchemaV12.join('\n');
    expect(sql, contains('CREATE TABLE tag_galleries'));
    expect(sql, contains("match_mode TEXT    NOT NULL DEFAULT 'all'"));
  });

  test('Windows 扫描：绝对路径、宽高、扩展名过滤、跳过 node_modules', () async {
    if (!Platform.isWindows) return;
    final temp = Directory.systemTemp.createTempSync('lc-desktop-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final artistDir = Directory('${temp.path}\\Artist_42')
      ..createSync(recursive: true);
    final icon = File(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    );
    // 用仓库里的图标当测试图：192×192 PNG。
    icon.copySync('${artistDir.path}\\111_p0.png');
    icon.copySync('${artistDir.path}\\222_p1.png');
    File('${temp.path}\\notes.txt').writeAsStringSync('not an image');
    final skipped = Directory('${temp.path}\\node_modules')..createSync();
    icon.copySync('${skipped.path}\\skip.png');

    final rows = await WindowsMediaBackend().listImages(root: temp.path);
    expect(rows.length, 2);
    expect(rows.every((row) => row.id == 0), isTrue);
    expect(rows.every((row) => row.absolutePath != null), isTrue);
    expect(rows.every((row) => row.width == 192 && row.height == 192), isTrue);
    expect(rows.map((row) => row.name).toSet(), {'111_p0.png', '222_p1.png'});
    expect(rows.map((row) => parseArtist(row.path)).toSet(), {
      ('42', 'Artist'),
    });
  });

  test('Windows 扫描：空/不存在目录返回空表', () async {
    if (!Platform.isWindows) return;
    final backend = WindowsMediaBackend();
    expect(await backend.listImages(root: ''), isEmpty);
    expect(
      await backend.listImages(
        root: '${Directory.systemTemp.path}\\definitely-not-here',
      ),
      isEmpty,
    );
  });
}
