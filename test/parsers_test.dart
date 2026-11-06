import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';

/// 解析器断言与桌面 Rust 测试（artworks.rs / artists.rs）、Kotlin 版互为镜像。
void main() {
  group('parsePid 接受侧', () {
    test('标准命名', () {
      expect(parsePid('123456_p0.jpg'), ('123456', 0));
      expect(parsePid('123456_p12.png'), ('123456', 12));
    });

    test('下载器后缀', () {
      expect(parsePid('123456_p0_master1200.jpg'), ('123456', 0));
    });

    test('完整路径', () {
      expect(parsePid(r'C:\pics\123456_p3.webp'), ('123456', 3));
      expect(parsePid('/storage/emulated/0/Pictures/pixez/123456_p3.webp'), ('123456', 3));
    });
  });

  group('parsePid 拒绝侧', () {
    test('非 pixiv 命名全部判不出', () {
      expect(parsePid('IMG_1234.jpg'), isNull);
      expect(parsePid('123456.jpg'), isNull);
      expect(parsePid('123456_p.jpg'), isNull);
      expect(parsePid('_p0.jpg'), isNull);
      expect(parsePid('pid_p0.jpg'), isNull);
    });
  });

  group('parseArtist', () {
    test('画师名_uid 目录', () {
      expect(
        parseArtist('/storage/emulated/0/Pictures/pixez/-273℃望歩_6657532/123456_p0.jpg'),
        ('6657532', '-273℃望歩'),
      );
    });

    test('判不出的目录', () {
      expect(parseArtist('/Pictures/12345678/123_p0.jpg'), isNull); // 全数字
      expect(parseArtist('/Pictures/画师abc/123_p0.jpg'), isNull); // 末尾非数字
      expect(parseArtist('/Pictures/画师123/123_p0.jpg'), isNull); // 没有下划线
      expect(parseArtist('123_p0.jpg'), isNull); // 没有父目录
    });
  });
}
