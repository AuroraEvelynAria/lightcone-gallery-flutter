import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'media_channel.dart';

/// 系统缩略图 ImageProvider。
///
/// 关键点全在这里：网格里**永远不解码原图**，而是向 MediaProvider 要它预生成
/// 的缩略图（命中系统缓存时只要几百微秒）。这是 pixez 那种「一滚到底不卡」
/// 的物料基础，也是 Kotlin 版当初漏掉的那块。
class MediaThumbnail extends ImageProvider<MediaThumbnail> {
  const MediaThumbnail(this.mediaId, {this.size = 320});

  final int mediaId;
  final int size;

  @override
  Future<MediaThumbnail> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MediaThumbnail>(this);

  @override
  ImageStreamCompleter loadImage(MediaThumbnail key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load(key, decode));
  }

  Future<ImageInfo> _load(MediaThumbnail key, ImageDecoderCallback decode) async {
    final bytes = await MediaChannel.thumbnail(key.mediaId, key.size);
    if (bytes == null) {
      throw StateError('系统缩略图不可用（mediaId=${key.mediaId}）');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaThumbnail && other.mediaId == mediaId && other.size == size;

  @override
  int get hashCode => Object.hash(mediaId, size);
}

/// 兜底：桌面导入的行没有 MediaStore 行号，用文件图按目标宽降采样解码。
ImageProvider imageProviderFor(int? mediaId, String path, {int size = 320}) {
  if (mediaId != null) return MediaThumbnail(mediaId, size: size);
  return ResizeImage.resizeIfNeeded(
    size,
    null,
    FileImage(File(path)),
  );
}

/// 作品卡缩略图：1~2 列这种大格直接按格宽从文件降采样解码 —— 系统缩略图是
/// 方形的，裁成 3:4 竖卡会被放大一轮；3 列以上格子小，继续走系统缩略图。
ImageProvider cardImageProvider({
  required int? mediaId,
  required String path,
  required int columns,
  required double cellPx,
  required int thumbSize,
}) {
  if (columns <= 2) {
    return ResizeImage.resizeIfNeeded(
      cellPx.round(),
      null,
      FileImage(File(path)),
    );
  }
  return imageProviderFor(mediaId, path, size: thumbSize);
}
