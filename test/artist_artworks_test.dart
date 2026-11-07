import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/pixiv/artist_artworks.dart';

void main() {
  test('插画与漫画都算，按 PID 降序', () {
    final pids = artworkIdsFromProfile({
      'error': false,
      'body': {
        'illusts': {'100': null, '300': 'x', '200': null},
        'manga': {'400': null, '50': null},
      },
    });
    expect(pids, ['400', '300', '200', '100', '50']);
  });

  test('去重（同一 PID 同时挂在两个桶里）', () {
    final pids = artworkIdsFromProfile({
      'body': {
        'illusts': {'7': null},
        'manga': {'7': null, '9': null},
      },
    });
    expect(pids, ['9', '7']);
  });

  test('错误信封 / 缺 body / 空桶返回空表', () {
    expect(artworkIdsFromProfile({'error': true}), isEmpty);
    expect(artworkIdsFromProfile({'body': 'no'}), isEmpty);
    expect(artworkIdsFromProfile({'body': {}}), isEmpty);
    expect(artworkIdsFromProfile(null), isEmpty);
    expect(
      artworkIdsFromProfile({
        'body': {
          'illusts': {'not-a-pid': null, '12': null},
        },
      }),
      ['12'],
    );
  });
}
