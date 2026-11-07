import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/pixiv/artist_avatar.dart';

void main() {
  test('优先 imageBig，回退 image', () {
    expect(
      avatarUrlFromUser({
        'error': false,
        'body': {
          'image': 'https://i.pximg.net/user-profile/img/small.jpg',
          'imageBig': 'https://i.pximg.net/user-profile/img/big.jpg',
        },
      }),
      'https://i.pximg.net/user-profile/img/big.jpg',
    );
    expect(
      avatarUrlFromUser({
        'body': {'image': 'https://i.pximg.net/user-profile/img/small.jpg'},
      }),
      'https://i.pximg.net/user-profile/img/small.jpg',
    );
  });

  test('只接受 pximg 的 https 地址', () {
    expect(
      avatarUrlFromUser({
        'body': {'imageBig': 'http://i.pximg.net/a.jpg'},
      }),
      isNull,
    );
    expect(
      avatarUrlFromUser({
        'body': {'imageBig': 'https://evil.example.com/a.jpg'},
      }),
      isNull,
    );
    expect(
      avatarUrlFromUser({
        'body': {'imageBig': 'https://i-cf.pximg.net/a.jpg'},
      }),
      'https://i-cf.pximg.net/a.jpg',
    );
  });

  test('错误信封 / 缺 body / 缺字段都返回 null', () {
    expect(avatarUrlFromUser({'error': true, 'message': 'x'}), isNull);
    expect(avatarUrlFromUser({'body': 'nope'}), isNull);
    expect(avatarUrlFromUser({'body': {}}), isNull);
    expect(avatarUrlFromUser(null), isNull);
  });
}
