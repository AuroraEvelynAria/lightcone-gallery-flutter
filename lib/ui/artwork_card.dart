import 'package:flutter/material.dart';

import 'blur_thumb.dart';
import 'page_badge.dart';

/// 一张作品卡：预览图 + 标题 + 画师 + 收藏心（pixez 的卡片结构）。
///
/// 心在图片**外面**的右下角（和 pixez 一样），点它只切收藏、不会打开详情；
/// 整张卡的其他区域点开详情。图片按原比例，瀑布流用它自己的高度。
class ArtworkCard extends StatelessWidget {
  const ArtworkCard({
    super.key,
    required this.image,
    required this.aspectRatio,
    required this.title,
    required this.artist,
    required this.favorite,
    required this.onTap,
    this.onFavorite,
    this.onLongPress,
    this.pageCount = 1,
    this.xRestrict = 0,
    this.heroTag,
    this.selected = false,
    this.selectionMode = false,
  });

  final ImageProvider image;
  final double aspectRatio;
  final String title;
  final String artist;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onLongPress;
  final int pageCount;
  final int xRestrict;
  final Object? heroTag;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(10);

    Widget picture = AspectRatio(
      aspectRatio: aspectRatio <= 0 ? 0.75 : aspectRatio,
      child: blurR18IfNeeded(
        context,
        xRestrict,
        Image(
          image: image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: const Center(
              child: Icon(Icons.broken_image_outlined, size: 24),
            ),
          ),
        ),
      ),
    );
    if (heroTag != null) {
      picture = Hero(tag: heroTag!, child: picture);
    }

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        onLongPress: onLongPress,
        // 桌面右键复用长按语义：图库=收藏，作品库=进入多选。
        onSecondaryTap: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                picture,
                if (pageCount > 1)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: PageBadge(count: pageCount),
                  ),
                if (selectionMode)
                  Positioned.fill(
                    child: ColoredBox(
                      color: selected ? Colors.black45 : Colors.black26,
                    ),
                  ),
                if (selectionMode && selected)
                  const Positioned(
                    left: 6,
                    top: 6,
                    child: Icon(
                      Icons.check_circle,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? '未命名' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          artist.isEmpty ? '未知画师' : artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!selectionMode && onFavorite != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      iconSize: 20,
                      tooltip: favorite ? '取消收藏' : '收藏',
                      onPressed: onFavorite,
                      icon: Icon(
                        favorite ? Icons.favorite : Icons.favorite_border,
                        color: favorite ? scheme.error : scheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
