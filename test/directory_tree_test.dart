import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';
import 'package:lightcone_flutter/media/directory_tree.dart';

MediaImageDto _row(String relativePath, String name) => MediaImageDto(
  id: name.hashCode,
  name: name,
  relativePath: relativePath,
  size: 1,
  modified: 0,
  width: 1,
  height: 1,
);

void main() {
  final rows = [
    _row('Pictures/pixez/Artist_1', '100_p0.jpg'),
    _row('Pictures/pixez/Artist_1', '100_p1.jpg'),
    _row('Pictures/pixez/Artist_2', '200_p0.jpg'),
    _row('Pictures/pixez', 'loose.jpg'),
    _row('Pictures/Gallery/owner', 'girl.jpg'),
    _row('DCIM/Camera', 'IMG_1.jpg'),
  ];

  group('DirectoryTree', () {
    final tree = DirectoryTree.fromRows(
      rows,
      initialPath: '/sdcard/Pictures/pixez',
    );

    test('根目录是内部存储', () {
      expect(tree.root, kStorageRoot);
      expect(tree.parentOf(kStorageRoot), isNull);
      expect(DirectoryTree.nameOf(kStorageRoot), '内部存储');
    });

    test('按图片行整理父子目录与计数', () {
      expect(tree.directCount('$kStorageRoot/Pictures/pixez'), 1);
      expect(tree.totalCount('$kStorageRoot/Pictures/pixez'), 4);
      expect(tree.totalCount('$kStorageRoot/Pictures'), 5);
      expect(tree.totalCount(kStorageRoot), 6);

      final pictures = tree.childrenOf(kStorageRoot);
      expect(
        pictures.map((e) => DirectoryTree.nameOf(e.path)),
        containsAll(['Pictures', 'DCIM']),
      );

      final underPictures = tree.childrenOf('$kStorageRoot/Pictures');
      final pixez = underPictures.firstWhere(
        (e) => DirectoryTree.nameOf(e.path) == 'pixez',
      );
      expect(pixez.directImages, 1);
      expect(pixez.totalImages, 4);

      final artist1 = tree
          .childrenOf('$kStorageRoot/Pictures/pixez')
          .firstWhere((e) => DirectoryTree.nameOf(e.path) == 'Artist_1');
      expect(artist1.directImages, 2);
      expect(artist1.totalImages, 2);
    });

    test('初始目录会从 /sdcard 归一化并进入树', () {
      final start = normalizeStoragePath('/sdcard/Pictures/pixez');
      expect(start, '$kStorageRoot/Pictures/pixez');
      expect(tree.contains(start), isTrue);
      expect(tree.parentOf(start), '$kStorageRoot/Pictures');
    });

    test('空目录也能浏览和选中', () {
      final empty = DirectoryTree.fromRows(
        const [],
        initialPath: '/storage/emulated/0/Pictures/empty',
      );
      expect(empty.contains('$kStorageRoot/Pictures/empty'), isTrue);
      expect(empty.totalCount('$kStorageRoot/Pictures/empty'), 0);
      final children = empty.childrenOf('$kStorageRoot/Pictures');
      expect(
        children.any((e) => DirectoryTree.nameOf(e.path) == 'empty'),
        isTrue,
      );
    });

    test('子目录按名字排序', () {
      final names = tree
          .childrenOf('$kStorageRoot/Pictures/pixez')
          .map((e) => DirectoryTree.nameOf(e.path))
          .toList();
      expect(names, ['Artist_1', 'Artist_2']);
    });
  });
}
