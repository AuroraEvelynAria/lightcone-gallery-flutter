import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/models.dart';

/// 竖排长图里一页的版面。
///
/// 普通页按原比例铺满宽度（本身就是一条长条）；横图如果只按宽度铺，
/// 在竖屏上会被压成很薄的一条 —— 3.5:1 的全景图只有屏宽的 28% 高，
/// 再被顶栏盖住一截，既难看也点不到。所以横页给一个更高的「舞台」：
///
/// - 舞台至少 `屏宽 * 0.56`，空出来的地方用同一张图的模糊放大当背景；
/// - 作品第一页如果是横图，舞台把顶栏高度让出来，图片不会再钻到状态栏下。
class PageStage {
  const PageStage({
    required this.height,
    required this.topInset,
    required this.wide,
    required this.ambient,
  });

  /// 舞台正文高度（不含 [topInset]）。
  final double height;

  /// 顶部让位：第一页横图时 = 状态栏 + 工具栏。
  final double topInset;

  /// 是否按横页处理（宽高比 > 1.2）。
  final bool wide;

  /// 是否需要在图片后面铺模糊背景（第一页让位或全景图留白时）。
  final bool ambient;

  double get totalHeight => topInset + height;

  static PageStage compute({
    required double screenWidth,
    required double screenHeight,
    required double aspectRatio,
    required double appBarBottom,
    required bool first,
  }) {
    final ratio = aspectRatio > 0 ? aspectRatio : 0.75;
    final fitHeight = screenWidth / ratio;
    if (ratio <= 1.2) {
      return PageStage(
        height: fitHeight,
        topInset: 0,
        wide: false,
        ambient: false,
      );
    }
    // 横屏时可视高度很矮，别让一页的舞台撑满整个屏幕
    final minStage = math.min(screenWidth * 0.56, screenHeight * 0.72);
    final height = math.max(fitHeight, minStage);
    final topInset = first ? appBarBottom : 0.0;
    return PageStage(
      height: height,
      topInset: topInset,
      wide: true,
      // 让位区需要背景；全景图在舞台里也会留出上下两条，同样铺模糊底
      ambient: topInset > 0 || height > fitHeight + 0.5,
    );
  }
}

/// 长图里的一页：图片 + 舞台 + 点击进检视器。
///
/// 抽成独立 widget 是为了能直接测「第一页横图是否让出了顶栏」和
/// 「点舞台能不能触发」—— 这两点正是在真机上出问题的地方。
class ArtworkPageTile extends StatelessWidget {
  const ArtworkPageTile({
    super.key,
    required this.page,
    required this.screenWidth,
    required this.screenHeight,
    required this.appBarBottom,
    required this.first,
    required this.providerFor,
    required this.onTap,
    this.heroTag,
    this.showR18 = false,
  });

  final ArtworkRow page;
  final double screenWidth;
  final double screenHeight;

  /// 状态栏 + 工具栏的底边（第一页横图时让位）。
  final double appBarBottom;
  final bool first;

  /// 按目标解码宽度取 ImageProvider（详情页与测试共用）。
  final ImageProvider Function(int cacheWidth) providerFor;
  final VoidCallback onTap;
  final Object? heroTag;
  final bool showR18;

  @override
  Widget build(BuildContext context) {
    final stage = PageStage.compute(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      aspectRatio: page.aspectRatio,
      appBarBottom: appBarBottom,
      first: first,
    );
    final cacheWidth = (screenWidth * MediaQuery.devicePixelRatioOf(context))
        .round();
    final sharp = Image(
      key: const ValueKey('page-sharp'),
      image: providerFor(cacheWidth),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
    );

    Widget tile;
    if (!stage.wide) {
      tile = SizedBox(
        width: screenWidth,
        height: stage.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            sharp,
            if (showR18)
              const Positioned(
                right: 10,
                bottom: 10,
                child: _Pill(text: 'R-18', danger: true),
              ),
          ],
        ),
      );
    } else {
      tile = SizedBox(
        width: screenWidth,
        height: stage.totalHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (stage.ambient) ...[
              // 背景按 1/8 尺寸解码再模糊：肉眼只能看到色块，成本可以忽略
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Image(
                  image: providerFor(math.max(64, cacheWidth ~/ 8)),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const ColoredBox(color: Color(0x73000000)),
            ],
            // 让位区留在背景上，真图从顶栏下方开始
            Padding(
              padding: EdgeInsets.only(top: stage.topInset),
              child: Center(child: sharp),
            ),
            if (showR18)
              const Positioned(
                right: 10,
                bottom: 10,
                child: _Pill(text: 'R-18', danger: true),
              ),
            const Positioned(
              left: 10,
              bottom: 10,
              child: _Pill(icon: Icons.open_in_full, text: '看全图'),
            ),
          ],
        ),
      );
    }

    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // 模糊底与留白也算点击区（栈里的 ColoredBox 会命中，但显式声明更稳）
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tile,
      ),
    );
    if (heroTag != null) {
      result = Hero(tag: heroTag!, child: result);
    }
    return result;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.danger = false});

  final String text;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 8 : 7, 3, 8, 3),
      decoration: BoxDecoration(
        color: danger ? const Color(0xCCB3261E) : Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
