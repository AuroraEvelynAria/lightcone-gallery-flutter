import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blur_thumb.dart';
import 'page_badge.dart';

/// 桌面点击卡片的修饰键状态：Ctrl/Meta = 加选，Shift = 连选。
typedef ArtworkTapModifiers = ({bool ctrl, bool shift});

/// 一张作品卡：预览图 + 标题 + 画师 + 收藏心（pixez 的卡片结构）。
///
/// 心在图片**外面**的右下角（和 pixez 一样），点它只切收藏、不会打开详情；
/// 整张卡的其他区域点开详情。图片按原比例，瀑布流用它自己的高度。
///
/// 桌面端：鼠标悬停时描边高亮；右键弹上下文菜单（[onContextMenu]）；
/// 点击时把修饰键状态交给 [onTapModified]（Ctrl 加选 / Shift 连选）。
/// 没给 [onTapModified] 的调用点（手机端）一律走 [onTap]，行为不变；
/// 没给 [onContextMenu] 的调用点右键退回 [onLongPress] 的老语义。
class ArtworkCard extends StatefulWidget {
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
    this.onContextMenu,
    this.onTapModified,
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

  /// 桌面右键：给出全局坐标，由调用方弹上下文菜单。
  final void Function(Offset globalPosition)? onContextMenu;

  /// 桌面点击：带上 Ctrl/Shift 状态，交给调用方决定加选还是连选。
  /// 给了它就不再走 [onTap]（桌面以修饰键语义为准，普通单击 = 单选）。
  final void Function(ArtworkTapModifiers modifiers)? onTapModified;
  final int pageCount;
  final int xRestrict;
  final Object? heroTag;
  final bool selected;
  final bool selectionMode;

  @override
  State<ArtworkCard> createState() => _ArtworkCardState();
}

class _ArtworkCardState extends State<ArtworkCard> {
  bool _hovered = false;

  /// 卡片被点击：桌面（[ArtworkCard.onTapModified]）带上修饰键，其余走 [onTap]。
  ///
  /// 修饰键从 `HardwareKeyboard` 读，而不是从点击事件本身 —— Flutter 的
  /// tab 手势不带键盘状态，鼠标点卡片时只能这样拿 Ctrl/Shift。
  void _handleTap() {
    final onModified = widget.onTapModified;
    if (onModified == null) {
      widget.onTap();
      return;
    }
    onModified((
      ctrl:
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(10);
    // 悬停：描边提亮 + 一线阴影，给鼠标一个「这里可以点」的反馈
    final hovered = _hovered && !widget.selectionMode;

    Widget picture = AspectRatio(
      aspectRatio: widget.aspectRatio <= 0 ? 0.75 : widget.aspectRatio,
      child: blurR18IfNeeded(
        context,
        widget.xRestrict,
        Image(
          image: widget.image,
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
    if (widget.heroTag != null) {
      picture = Hero(tag: widget.heroTag!, child: picture);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Material(
        color: scheme.surfaceContainerLow,
        elevation: hovered ? 3 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: hovered
                ? scheme.primary.withValues(alpha: 0.65)
                : scheme.outlineVariant.withValues(alpha: 0.55),
            width: hovered ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          // 桌面右键：优先弹上下文菜单；没给的屏退回长按语义。
          onSecondaryTapDown: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          onSecondaryTap: widget.onContextMenu != null
              ? null
              : widget.onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  picture,
                  if (widget.pageCount > 1)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: PageBadge(count: widget.pageCount),
                    ),
                  if (widget.selectionMode)
                    Positioned.fill(
                      child: ColoredBox(
                        color: widget.selected
                            ? Colors.black45
                            : Colors.black26,
                      ),
                    ),
                  if (widget.selectionMode && widget.selected)
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
                            widget.title.isEmpty ? '未命名' : widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.artist.isEmpty ? '未知画师' : widget.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.selectionMode && widget.onFavorite != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        iconSize: 20,
                        tooltip: widget.favorite ? '取消收藏' : '收藏',
                        onPressed: widget.onFavorite,
                        icon: Icon(
                          widget.favorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: widget.favorite ? scheme.error : scheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
