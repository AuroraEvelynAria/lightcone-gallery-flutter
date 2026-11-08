import 'package:flutter/material.dart';

import '../media/directory_tree.dart';
import '../media/media_channel.dart';

/// 应用内图库目录选择器。
///
/// 不用 SAF 的 `ACTION_OPEN_DOCUMENT_TREE`：在中文 Android 环境里，「李跳跳 /
/// GKD」这类无障碍自动点击器会把系统选择器的「使用此文件夹 / 允许」瞬间点掉，
/// 目录树根本来不及展开（真机复现）。这里直接用 MediaStore 的全量图片行整理
/// 出目录树，点哪层进哪层，不经过任何系统对话框。
Future<String?> showDirectoryPicker(
  BuildContext context, {
  required String initialPath,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DirectoryPickerDialog(initialPath: initialPath),
  );
}

class _DirectoryPickerDialog extends StatefulWidget {
  const _DirectoryPickerDialog({required this.initialPath});

  final String initialPath;

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  DirectoryTree? _tree;
  String? _current;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var granted = await MediaChannel.hasPermission();
      if (!granted) {
        // 首次启动时 Onboarding 可能正在请求权限：这里再兜一次，失败就报错。
        try {
          await MediaChannel.requestPermission();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 300));
        granted = await MediaChannel.hasPermission();
      }
      if (!granted) {
        throw '没有相册读取权限';
      }
      final rows = await MediaChannel.listImages();
      final tree = DirectoryTree.fromRows(
        rows,
        initialPath: widget.initialPath,
      );
      final start = normalizeStoragePath(widget.initialPath);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _current = tree.contains(start) ? start : tree.root;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.55).clamp(
      300.0,
      580.0,
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('选择图库目录'),
      content: SizedBox(
        width: double.maxFinite,
        height: height,
        child: _buildContent(theme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _current == null
              ? null
              : () => Navigator.of(context).pop(_current),
          child: const Text('使用此目录'),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text('读取目录…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final tree = _tree!;
    final current = _current!;
    final children = tree.childrenOf(current);
    final parent = tree.parentOf(current);
    final direct = tree.directCount(current);
    final total = tree.totalCount(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '上一级',
              onPressed: parent == null
                  ? null
                  : () => setState(() => _current = parent),
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(
              child: Text(
                current,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 4),
          child: Text(
            total == 0 ? '这个目录还没有图片' : '直接 $direct 张 · 含子目录 $total 张',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '没有子目录了\n可以直接使用当前目录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: children.length,
                  itemBuilder: (context, index) {
                    final entry = children[index];
                    final name = DirectoryTree.nameOf(entry.path);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.totalImages == 0
                            ? '空目录'
                            : entry.directImages == 0
                            ? '含子目录 ${entry.totalImages} 张'
                            : '${entry.directImages} 张 · 含子目录 ${entry.totalImages} 张',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => _current = entry.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
