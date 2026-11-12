import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_card.dart';
import 'artwork_detail_screen.dart';
import 'desktop/artwork_menu.dart';
import 'viewer_screen.dart';

/// 通用图库：pixez 式作品卡瀑布流 + 分页（预览 / 标题 / 画师 / 收藏心）。
/// 网格里只显示**系统缩略图**（见 MediaThumbnail），原图只在检视器里解一次。
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.state});

  final AppState state;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const _pageSize = 120;

  final _rows = <ImageRow>[];
  final _controller = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  bool _favoriteOnly = false;
  bool _descending = true;

  /// AI 三态：null 不限 / true 仅 AI / false 仅非 AI。
  bool? _aiOnly;
  bool _hideR18 = false;
  String? _artistUid;
  String? _artistName;
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
      setState(() {}); // 扫描进行中等 UI 状态
    }
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 800) _loadMore();
  }

  /// 选画师：按作品数降序列出，量大的人排前面。
  Future<void> _pickArtist() async {
    final artists = await widget.state.repo.artistCounts(limit: 300);
    if (!mounted) return;
    if (artists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有识别到画师，先扫描或补全元数据')),
      );
      return;
    }
    final picked = await showModalBottomSheet<ArtistCount>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            return ListTile(
              dense: true,
              title: Text(
                a.name.isEmpty ? a.uid : a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(a.uid),
              trailing: Text(a.count.toString()),
              onTap: () => Navigator.of(context).pop(a),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _artistUid = picked.uid;
      _artistName = picked.name.isEmpty ? picked.uid : picked.name;
    });
    _reload();
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
    final page = await widget.state.repo.imagesPage(
      favoriteOnly: _favoriteOnly,
      aiOnly: _aiOnly,
      xRestrict: _hideR18 ? 0 : -1,
      artistUid: _artistUid,
      descending: _descending,
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

  void _openItem(int index) {
    final row = _rows[index];
    // pixez 命名的图有作品可查：进详情页（标题 / 画师 / 标签 / 收藏）；
    // 其余图片退回纯检视器。
    final parsed = row.pid == null ? null : parsePid(row.filename);
    if (parsed != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtworkDetailScreen(
            state: widget.state,
            pid: parsed.$1,
            initialPage: parsed.$2,
            heroTag: 'img-${row.id}',
            onFavoriteChanged: (favorite) {
              if (!mounted) return;
              final at = _rows.indexWhere((r) => r.id == row.id);
              if (at < 0) return;
              setState(() => _rows[at] = _rows[at].copyWith(isFavorite: favorite));
            },
          ),
        ),
      );
      return;
    }
    final items = _rows
        .map((row) => ViewerItem(
              path: row.path,
              title: row.filename,
              aspectRatio: (row.width != null &&
                      row.height != null &&
                      row.height! > 0)
                  ? row.width! / row.height!
                  : 0,
            ))
        .toList(growable: false);
    Navigator.of(context).push(viewerRoute(items: items, initialIndex: index));
  }

  String _titleOf(ImageRow row) {
    final title = row.title?.trim() ?? '';
    return title.isEmpty ? row.filename : title;
  }

  String _artistOf(ImageRow row) {
    final name = (row.artistName ?? row.artistAccount ?? '').trim();
    if (name.isNotEmpty) return name;
    return parseArtist(row.path)?.$2 ?? '未分类';
  }

  Future<void> _toggleFavorite(int index) async {
    final row = _rows[index];
    final next = !row.isFavorite;
    setState(() => _rows[index] = row.copyWith(isFavorite: next));
    final pid = row.pid;
    if (pid == null) {
      await widget.state.repo.setFavorite(row.id, next);
      return;
    }
    final updated = await widget.state.repo.setPidFavorite(pid, next);
    if (!mounted) return;
    if (updated == 0) {
      final at = _rows.indexWhere((r) => r.id == row.id);
      if (at >= 0) {
        setState(() => _rows[at] = _rows[at].copyWith(isFavorite: !next));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏失败：这张不在图库里')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = AppSettingsScope.of(context).gridColumns;
    final media = MediaQuery.of(context);
    final effective = columns > 0 ? columns : (media.size.width / 120).round().clamp(2, 6);
    // 方形缩略图会被竖卡裁成 3:4：按长边要，别只按格宽
    final cellPx = media.size.width * media.devicePixelRatio / effective;
    final thumbSize = (cellPx * 1.6).round().clamp(320, 1024);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('收藏'),
                        selected: _favoriteOnly,
                        onSelected: (value) {
                          setState(() => _favoriteOnly = value);
                          _reload();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(_descending ? '最新' : '最早'),
                        selected: _descending,
                        onSelected: (value) {
                          setState(() => _descending = value);
                          _reload();
                        },
                      ),
                      const SizedBox(width: 8),
                      // 三个筛选维度按「能砍掉多少」排序排的：
                      // 画师（本地库 99.5% 有画师）、AI（约六成）、R-18。
                      FilterChip(
                        label: Text(
                          _aiOnly == null
                              ? 'AI'
                              : (_aiOnly! ? '仅 AI' : '非 AI'),
                        ),
                        selected: _aiOnly != null,
                        onSelected: (_) {
                          setState(() {
                            _aiOnly = _aiOnly == null
                                ? true
                                : (_aiOnly! ? false : null);
                          });
                          _reload();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('隐藏 R-18'),
                        selected: _hideR18,
                        onSelected: (value) {
                          setState(() => _hideR18 = value);
                          _reload();
                        },
                      ),
                      const SizedBox(width: 8),
                      if (_artistUid == null)
                        ActionChip(
                          avatar: const Icon(Icons.person_outline, size: 18),
                          label: const Text('画师'),
                          onPressed: _pickArtist,
                        )
                      else
                        InputChip(
                          avatar: const Icon(Icons.person, size: 18),
                          label: Text(
                            _artistName ?? '画师',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () {
                            setState(() {
                              _artistUid = null;
                              _artistName = null;
                            });
                            _reload();
                          },
                        ),
                    ],
                  ),
                ),
              ),
              // 这里原来有个「已加载 N 张」的计数，把「画师」chip 挤出了屏幕。
              // 计数信息量低（滚动时自己就能感知位置），让位给筛选项。
            ],
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? _empty()
              : MasonryGridView.count(
                  controller: _controller,
                  padding: const EdgeInsets.all(8),
                  crossAxisCount: effective,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return ArtworkCard(
                      image: cardImageProvider(
                        mediaId: row.mediaId,
                        path: row.path,
                        columns: effective,
                        cellPx: cellPx,
                        thumbSize: thumbSize,
                      ),
                      aspectRatio: row.aspectRatio,
                      title: _titleOf(row),
                      artist: _artistOf(row),
                      favorite: row.isFavorite,
                      pageCount: row.pageTotal,
                      xRestrict: row.xRestrict,
                      heroTag: 'img-${row.id}',
                      onTap: () => _openItem(index),
                      onLongPress: () => _toggleFavorite(index),
                      onFavorite: () => _toggleFavorite(index),
                      onContextMenu: (position) => showArtworkContextMenu(
                        context: context,
                        globalPosition: position,
                        pid: row.pid,
                        favorite: row.isFavorite,
                        primaryPath: row.path,
                        onOpen: () => _openItem(index),
                        onToggleFavorite: () => _toggleFavorite(index),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _empty() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('图库还是空的'),
          const SizedBox(height: 4),
          Text(
            '右上角 ↻ 扫描图库，或进设置导入桌面备份',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

