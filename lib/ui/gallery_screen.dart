import 'package:flutter/material.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_detail_screen.dart';
import 'blur_thumb.dart';
import 'page_badge.dart';
import 'viewer_screen.dart';

/// 通用图库：方格网格 + 分页。网格里只显示**系统缩略图**（见 MediaThumbnail），
/// 原图只在检视器里解一次。
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
              if (!mounted || index >= _rows.length) return;
              setState(() {
                _rows[index] = ImageRow(
                  id: row.id,
                  libraryId: row.libraryId,
                  path: row.path,
                  filename: row.filename,
                  fileSize: row.fileSize,
                  modifiedAt: row.modifiedAt,
                  isFavorite: favorite,
                  rating: row.rating,
                  width: row.width,
                  height: row.height,
                  pid: row.pid,
                  artistUid: row.artistUid,
                  mediaId: row.mediaId,
                  pageTotal: row.pageTotal,
                  xRestrict: row.xRestrict,
                );
              });
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(items: items, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = AppSettingsScope.of(context).gridColumns;
    final media = MediaQuery.of(context);
    final effective = columns > 0 ? columns : (media.size.width / 120).round().clamp(2, 6);
    // 缩略图按「每格实际像素」要：2 列时系统缩略图给到 540px，5 列只要 216px
    final thumbSize =
        (media.size.width * media.devicePixelRatio / effective).round().clamp(200, 640);
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
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_descending ? '最新' : '最早'),
                selected: _descending,
                onSelected: (value) {
                  _descending = value;
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
        Expanded(
          child: _rows.isEmpty
              ? _empty()
              : GridView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.all(6),
                  // 每格上限 120dp：手机上约 3 列（设置里可固定 3/4/5 列）
                  gridDelegate: columns > 0
                      ? SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        )
                      : const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                  // 预渲染一屏半，快速滚动时缩略图先就位
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return _Tile(
                      row: row,
                      thumbSize: thumbSize,
                      onTap: () => _openItem(index),
                      onLongPress: () async {
                        // 卡片代表整个作品：收藏状态写到这个 PID 的所有页
                        final pid = row.pid;
                        if (pid != null) {
                          await widget.state.repo.setPidFavorite(pid, !row.isFavorite);
                        } else {
                          await widget.state.repo.setFavorite(row.id, !row.isFavorite);
                        }
                        if (!mounted) return;
                        setState(() {
                          _rows[index] = ImageRow(
                            id: row.id,
                            libraryId: row.libraryId,
                            path: row.path,
                            filename: row.filename,
                            fileSize: row.fileSize,
                            modifiedAt: row.modifiedAt,
                            isFavorite: !row.isFavorite,
                            rating: row.rating,
                            width: row.width,
                            height: row.height,
                            pid: row.pid,
                            artistUid: row.artistUid,
                            mediaId: row.mediaId,
                            pageTotal: row.pageTotal,
                            xRestrict: row.xRestrict,
                          );
                        });
                      },
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.row,
    required this.thumbSize,
    required this.onTap,
    required this.onLongPress,
  });

  final ImageRow row;
  final int thumbSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: 'img-${row.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              blurR18IfNeeded(
                context,
                row.xRestrict,
                Image(
                  image: imageProviderFor(row.mediaId, row.path, size: thumbSize),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined, size: 20),
                  ),
                ),
              ),              if (row.isFavorite)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Icon(
                    Icons.favorite,
                    size: 14,
                    color: Theme.of(context).colorScheme.error,
                    shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                  ),
                ),
              if (row.pageTotal > 1)
                Positioned(
                  left: 3,
                  bottom: 3,
                  child: PageBadge(count: row.pageTotal),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
