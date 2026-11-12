import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../media/media_channel.dart';

/// 作品卡的**右键上下文菜单**（桌面端）。
///
/// 每个屏把「这一格当前能做什么」拼成回调传进来，菜单只管展示：能做的
/// 才出现，做不了的（比如图库里的图没有 PID）直接不给那一项，避免点下去
/// 才弹「失败」。
///
/// 以前桌面是「右键 = 长按」（图库切收藏、作品库进多选）—— 那只是没做菜单
/// 时的临时语义，鼠标用户右键的预期是弹菜单。
///
/// 作品库多选选中多件时，右键落在选区内不该只对一张生效：传入
/// [batchCount]（>1）会把「收藏 / 移出」换成作用于整个选区的批量项，
/// 并把单件的「打开详情」等项收起 —— 和文件管理器的习惯一致。
Future<void> showArtworkContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  String? pid,
  required bool favorite,
  String? primaryPath,
  VoidCallback? onOpen,
  VoidCallback? onToggleFavorite,
  VoidCallback? onRemove,
  int batchCount = 0,
  VoidCallback? onBatchFavorite,
  VoidCallback? onBatchRemove,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject();
  final box = overlay is RenderBox ? overlay : null;
  if (box == null) return;

  // 选区里有 2 件以上才算批量；只选了右键这一张仍按单件走。
  final batch = batchCount > 1;

  final selection = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & box.size,
    ),
    items: [
      if (!batch && onOpen != null)
        const PopupMenuItem(value: 'open', child: Text('打开详情')),
      if (!batch && onToggleFavorite != null)
        PopupMenuItem(
          value: 'favorite',
          child: Text(favorite ? '取消收藏' : '收藏'),
        ),
      if (batch && onBatchFavorite != null)
        PopupMenuItem(
          value: 'batch-favorite',
          child: Text('收藏选中的 $batchCount 件'),
        ),
      const PopupMenuDivider(),
      if (!batch && pid != null)
        const PopupMenuItem(value: 'copy-pid', child: Text('复制 PID')),
      if (!batch && primaryPath != null)
        const PopupMenuItem(value: 'copy-path', child: Text('复制文件路径')),
      if (!batch && primaryPath != null)
        const PopupMenuItem(
          value: 'reveal',
          child: Text('在资源管理器中显示'),
        ),
      if (batch && onBatchRemove != null) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'batch-remove',
          child: Text('移出选中的 $batchCount 件'),
        ),
      ],
      if (!batch && onRemove != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('移出作品库')),
      ],
    ],
  );
  if (selection == null || !context.mounted) return;

  // 弹菜单是 async：await 回来后 context 可能已失效，统一用 mounted 守卫。
  final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;

  switch (selection) {
    case 'open':
      onOpen?.call();
    case 'favorite':
      onToggleFavorite?.call();
    case 'batch-favorite':
      onBatchFavorite?.call();
    case 'batch-remove':
      onBatchRemove?.call();
    case 'copy-pid':
      await Clipboard.setData(ClipboardData(text: pid!));
      messenger?.showSnackBar(SnackBar(content: Text('已复制 PID $pid')));
    case 'copy-path':
      await Clipboard.setData(ClipboardData(text: primaryPath!));
      messenger?.showSnackBar(const SnackBar(content: Text('已复制文件路径')));
    case 'reveal':
      await MediaChannel.revealInExplorer([primaryPath!]);
    case 'remove':
      onRemove?.call();
  }
}
