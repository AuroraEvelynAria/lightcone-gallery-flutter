import 'dart:io';

import 'package:flutter/material.dart';

import '../media/media_channel.dart';

/// 检视条目：路径 + 标题（图库与作品库共用同一个检视器）。
class ViewerItem {
  const ViewerItem({
    required this.path,
    required this.title,
    this.aspectRatio = 0,
  });

  final String path;
  final String title;

  /// 宽 / 高；0 = 未知。双击放大时用来算「铺满屏高」的倍率。
  final double aspectRatio;
}

/// 全屏检视器：左右翻页（PageView）+ 双指缩放（InteractiveViewer）。
/// 原图只在这里解码 —— 网格里永远不碰大图。
///
/// 顶栏带分享与「设为壁纸」，直接对当前这张图操作。
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<ViewerItem> items;
  final int initialIndex;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// 每页一个变换控制器：双击在「整张」和「铺满屏高」之间切换。
  final _transforms = <int, TransformationController>{};

  TransformationController _transformFor(int index) =>
      _transforms.putIfAbsent(index, () => TransformationController());

  @override
  void dispose() {
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// 以屏幕中心为锚点缩放，双击切回整张。
  void _toggleZoom(int index, Size screen) {
    final controller = _transformFor(index);
    final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
    final target = zoomed
        ? 1.0
        : fillHeightScale(widget.items[index].aspectRatio, screen);
    final center = Offset(screen.width / 2, screen.height / 2);
    // 绕屏幕中心缩放：x' = s·x + c(1-s)，直接写矩阵，避开已废弃的
    // Matrix4.translate / scale。
    controller.value = Matrix4.identity()
      ..setEntry(0, 0, target)
      ..setEntry(1, 1, target)
      ..setEntry(0, 3, center.dx * (1 - target))
      ..setEntry(1, 3, center.dy * (1 - target));
  }

  Future<void> _share({bool asFile = false}) async {
    final item = widget.items[_index];
    final ok = await MediaChannel.shareImages(
      [item.path],
      text: item.title,
      asFile: asFile,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('分享失败：没有可用的应用或文件不存在')),
    );
  }

  Future<void> _saveToGallery() async {
    final item = widget.items[_index];
    final name = item.path.split('/').last;
    final ok = await MediaChannel.saveToGallery(item.path, name: name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已保存到相册 Pictures/LightCone' : '保存失败')),
    );
  }

  Future<void> _setWallpaper() async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('设为壁纸'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'home'),
            child: const Text('主屏幕'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'lock'),
            child: const Text('锁屏'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'both'),
            child: const Text('主屏幕 + 锁屏'),
          ),
        ],
      ),
    );
    if (target == null) return;
    final ok = await MediaChannel.setWallpaper(
      widget.items[_index].path,
      target: target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已设为壁纸' : '设置壁纸失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享',
            onPressed: _share,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'wallpaper':
                  _setWallpaper();
                case 'share-file':
                  _share(asFile: true);
                case 'save':
                  _saveToGallery();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'wallpaper', child: Text('设为壁纸…')),
              PopupMenuItem(value: 'share-file', child: Text('以文件分享（不压缩）')),
              PopupMenuItem(value: 'save', child: Text('保存原图到相册')),
            ],
          ),
        ],
        title: Text(
          '${_index + 1} / ${widget.items.length} · ${widget.items[_index].title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final screen = MediaQuery.sizeOf(context);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 横图整张看的时候只有一条，双击铺满屏高再左右拖
                onDoubleTap: () => _toggleZoom(index, screen),
                child: InteractiveViewer(
                  transformationController: _transformFor(index),
                  minScale: 1,
                  maxScale: 10,
                  clipBehavior: Clip.none,
                  child: Center(
                    child: Image.file(
                      File(item.path),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              color: Colors.white54, size: 48),
                          SizedBox(height: 8),
                          Text('图片读取失败',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // 只有横图需要提示：竖图本来就没有「放大到屏高」的必要
          if (widget.items[_index].aspectRatio > 1.4)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: const IgnorePointer(
                child: Center(
                  child: _ViewerHint(text: '双击切换大小 · 拖动查看'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 双击「铺满屏高」的倍率：横图按宽度显示后，要放大多少才占满屏高。
/// 竖图本来就接近屏高，给 2× 的手感；比例未知也按 2×。
@visibleForTesting
double fillHeightScale(double aspectRatio, Size screen) {
  if (aspectRatio <= 0 || screen.height <= 0) return 2;
  final screenAspect = screen.width / screen.height;
  final displayedHeight = aspectRatio >= screenAspect
      ? screen.width / aspectRatio
      : screen.height;
  return (screen.height / displayedHeight).clamp(2.0, 10.0);
}

class _ViewerHint extends StatelessWidget {
  const _ViewerHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
