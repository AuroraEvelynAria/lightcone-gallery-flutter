import 'dart:io';

import 'package:flutter/material.dart';

import '../media/media_channel.dart';

/// 检视条目：路径 + 标题（图库与作品库共用同一个检视器）。
class ViewerItem {
  const ViewerItem({required this.path, required this.title});

  final String path;
  final String title;
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            clipBehavior: Clip.none,
            child: Center(
              child: Image.file(
                File(item.path),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                    SizedBox(height: 8),
                    Text('图片读取失败', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
