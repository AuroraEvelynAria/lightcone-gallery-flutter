import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_card.dart';
import 'artwork_detail_screen.dart';

/// 作品库：瀑布流（每格高度 = 列宽 × 原图高宽比）。缩略图仍走系统缩略图，
/// 比例来自 MediaStore 的 WIDTH/HEIGHT，所以布局不跳、滚动不卡。
class ArtworksScreen extends StatefulWidget {
  const ArtworksScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ArtworksScreen> createState() => _ArtworksScreenState();
}

class _ArtworksScreenState extends State<ArtworksScreen> {
  static const _pageSize = 120;

  final _rows = <ArtworkRow>[];
  final _controller = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  bool _favoriteOnly = false;
  bool _selecting = false;
  final _selected = <int>{};
  int _lastVersion = 0;

  @override
  void initState() {
    super.initState();
    _lastVersion = widget.state.dataVersion;
    widget.state.addListener(_onStateChanged);
    _controller.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_lastVersion != widget.state.dataVersion) {
      _lastVersion = widget.state.dataVersion;
      _reload();
    } else {
      setState(() {});
    }
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 900) _loadMore();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _rows.clear();
      _hasMore = true;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    final page = await widget.state.repo.artworksPage(
      favoriteOnly: _favoriteOnly,
      offset: _rows.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _rows.addAll(page);
      _loading = false;
      _hasMore = page.length >= _pageSize;
    });
  }

  void _openDetail(int index) {
    final row = _rows[index];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtworkDetailScreen(
          state: widget.state,
          pid: row.pid,
          initialPage: row.page,
          heroTag: 'art-${row.id}',
          onFavoriteChanged: (favorite) {
            if (!mounted) return;
            final at = _rows.indexWhere((r) => r.id == row.id);
            if (at >= 0) setState(() => _rows[at] = _rows[at].copyWith(favorite: favorite));
          },
        ),
      ),
    );
  }

  String _titleOf(ArtworkRow row) {
    final title = row.title?.trim() ?? '';
    return title.isEmpty ? 'PID ${row.pid}' : title;
  }

  String _artistOf(ArtworkRow row) {
    final name = (row.artistName ?? row.artistAccount ?? '').trim();
    if (name.isNotEmpty) return name;
    return parseArtist(row.originalPath)?.$2 ?? '未知画师';
  }

  Future<void> _toggleFavorite(int index) async {
    final row = _rows[index];
    final next = !row.favorite;
    setState(() => _rows[index] = row.copyWith(favorite: next));
    final updated = await widget.state.repo.setPidFavorite(row.pid, next);
    if (!mounted) return;
    if (updated == 0) {
      final at = _rows.indexWhere((r) => r.id == row.id);
      if (at >= 0) setState(() => _rows[at] = _rows[at].copyWith(favorite: !next));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张不在图库里，收藏只对图库图片生效')),
      );
    }
  }

  /// 长按进入多选；再点卡片是勾选/取消，不打开详情。
  void _startSelect(ArtworkRow row) {
    setState(() {
      _selecting = true;
      _selected.add(row.id);
    });
  }

  void _toggleSelect(ArtworkRow row) {
    setState(() {
      if (!_selected.remove(row.id)) _selected.add(row.id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _favoriteSelected() async {
    final pids = _rows
        .where((row) => _selected.contains(row.id))
        .map((row) => row.pid)
        .toSet()
        .toList(growable: false);
    if (pids.isEmpty) return;
    await widget.state.repo.setPidsFavorite(pids, true);
    final count = _selected.length;
    _exitSelect();
    widget.state.bumpData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已收藏 $count 件')),
    );
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList(growable: false);
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移出 ${ids.length} 件？'),
        content: const Text('只从作品库移除（原图不会被删除），重扫也不会收回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await widget.state.repo.removeArtworks(ids);
    _exitSelect();
    widget.state.bumpData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('收藏'),
                selected: _favoriteOnly,
                onSelected: (value) {
                  _favoriteOnly = value;
                  _reload();
                },
              ),
              const Spacer(),
              if (_rows.isNotEmpty)
                Text(
                  '${_rows.length}${_hasMore ? '+' : ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
        if (_selecting) _buildSelectionBar(context),
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '取消选择',
                onPressed: _exitSelect,
              ),
              Text('已选 ${_selected.length}'),
              const Spacer(),
              TextButton.icon(
                onPressed: _favoriteSelected,
                icon: const Icon(Icons.favorite_border),
                label: const Text('收藏'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _removeSelected,
                icon: const Icon(Icons.delete_outline),
                label: const Text('移出'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_rows.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_favoriteOnly ? '还没有收藏的作品' : '作品库还是空的'),
            const SizedBox(height: 4),
            Text(
              _favoriteOnly
                  ? '在详情页点「收藏」就会出现在这里'
                  : '右上角 ↻ 扫描图库，收集当前目录里的作品',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferred = AppSettingsScope.of(context).gridColumns;
        final columns = preferred > 0
            ? preferred
            : (constraints.maxWidth / 120).round().clamp(2, 6);
        final media = MediaQuery.of(context);
        // 方形系统缩略图会被竖卡裁成 3:4 —— 请求长边而不是格宽，否则看着糊
        final cellPx = media.size.width * media.devicePixelRatio / columns;
        final thumbSize = (cellPx * 1.6).round().clamp(320, 1024);
        return MasonryGridView.count(
          controller: _controller,
          padding: const EdgeInsets.all(8),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: _rows.length,
          itemBuilder: (context, index) {
            final row = _rows[index];
            final selected = _selected.contains(row.id);
            return ArtworkCard(
              image: cardImageProvider(
                mediaId: row.mediaId,
                path: row.originalPath,
                columns: columns,
                cellPx: cellPx,
                thumbSize: thumbSize,
              ),
              aspectRatio: row.aspectRatio,
              title: _titleOf(row),
              artist: _artistOf(row),
              favorite: row.favorite,
              pageCount: row.pageTotal,
              xRestrict: row.xRestrict ?? 0,
              heroTag: 'art-${row.id}',
              selected: selected,
              selectionMode: _selecting,
              onTap: () {
                if (_selecting) {
                  _toggleSelect(row);
                } else {
                  _openDetail(index);
                }
              },
              onLongPress: () {
                if (_selecting) {
                  _toggleSelect(row);
                } else {
                  _startSelect(row);
                }
              },
              onFavorite: () => _toggleFavorite(index),
            );
          },
        );
      },
    );
  }
}
