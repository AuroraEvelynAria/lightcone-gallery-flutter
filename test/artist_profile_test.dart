import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';

void main() {
  group('formatBytes', () {
    test('零与字节', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
    });

    test('进位到 KB / MB / GB', () {
      expect(formatBytes(1024), '1.00 KB');
      expect(formatBytes(5 * 1024 * 1014), '4.95 MB');
      expect(formatBytes(620 * 1024 * 1024), '620 MB');
      expect(formatBytes(11368500669), '10.6 GB');
    });
  });

  group('ArtistProfile', () {
    test('名字缺失时退回 UID', () {
      final profile = ArtistProfile(
        uid: '123',
        name: '  ',
        artworks: 0,
        pages: 0,
        favorites: 0,
        bytes: 0,
      );
      expect(profile.displayName, 'UID 123');
    });

    test('上传日期取前 10 位', () {
      final profile = ArtistProfile(
        uid: '1',
        name: 'x',
        artworks: 1,
        pages: 1,
        favorites: 0,
        bytes: 0,
        firstDate: '2020-03-20T06:21:00+00:00',
        lastDate: '2026-10-03T15:30:00+00:00',
      );
      expect(profile.firstDay, '2020-03-20');
      expect(profile.lastDay, '2026-10-03');
    });

    test('日期缺失 / 太短返回 null', () {
      final profile = ArtistProfile(
        uid: '1',
        name: 'x',
        artworks: 1,
        pages: 1,
        favorites: 0,
        bytes: 0,
        firstDate: '2020-03',
      );
      expect(profile.firstDay, isNull);
      expect(profile.lastDay, isNull);
    });
  });
}
