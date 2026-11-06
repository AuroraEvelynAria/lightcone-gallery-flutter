import 'dart:io';

import 'package:flutter/material.dart';

/// 检视条目：路径 + 标题（图库与作品库共用同一个检视器）。
class ViewerItem {
  const ViewerItem({required this.path, required this.title});

  final String path;
  final String title;
}

/// 全屏检视器：左右翻页（PageView）+ 双指缩放（InteractiveViewer）。
/// 原图只在这里解码 —— 网格里永远不碰大图。
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
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
