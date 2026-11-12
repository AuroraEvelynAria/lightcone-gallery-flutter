import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_card.dart';
import 'artwork_detail_screen.dart';
import 'desktop/artwork_menu.dart';

/// 画师 / 标签筛选后的作品页（复用作品库的瀑布流）。
class FilteredArtworksScreen extends StatefulWidget {
  const FilteredArtworksScreen({
    super.key,
    required this.state,
    required this.title,
    this.artistUid,
    this.tags = const [],
    this.tagsMatchAny = false,
    this.aiOnly = false,
  });

  final AppState state;
  final String title;
  final String? artistUid;
  final List<String> tags;
  final bool tagsMatchAny;

  /// 只看 AI 生成（Pixiv 标记 ∪ AI 标签）。
  final bool aiOnly;

  @override
  State<FilteredArtworksScreen> createState() => _FilteredArtworksScreenState();
}

class _FilteredArtworksScreenState extends State<FilteredArtworksScreen> {
  static const _pageSize = 120;

  final _rows = <ArtworkRow>[];
  final _controller = ScrollController();
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 900) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    final page = await widget.state.repo.artworksPage(
      artistUid: widget.artistUid,
      tags: widget.tags,
      tagsMatchAny: widget.tagsMatchAny,
      aiOnly: widget.aiOnly,
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

  void _openDetail(ArtworkRow row) {
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
            if (at >= 0) {
              setState(
                () => _rows[at] = _rows[at].copyWith(favorite: favorite),
              );
            }
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

  Future<void> _toggleFavorite(ArtworkRow row) async {
    final index = _rows.indexWhere((r) => r.id == row.id);
    if (index < 0) return;
    final next = !row.favorite;
    setState(() => _rows[index] = row.copyWith(favorite: next));
    final updated = await widget.state.repo.setPidFavorite(row.pid, next);
    if (!mounted || updated > 0) return;
    final at = _rows.indexWhere((r) => r.id == row.id);
    if (at >= 0) {
      setState(() => _rows[at] = _rows[at].copyWith(favorite: !next));
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('这张不在图库里，收藏只对图库图片生效')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final preferred = AppSettingsScope.of(context).gridColumns;
          final columns = preferred > 0
              ? preferred
              : (constraints.maxWidth / 120).round().clamp(2, 6);
          final media = MediaQuery.of(context);
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
                onTap: () => _openDetail(row),
                onFavorite: () => _toggleFavorite(row),
                onContextMenu: (position) => showArtworkContextMenu(
                  context: context,
                  globalPosition: position,
                  pid: row.pid,
                  favorite: row.favorite,
                  primaryPath: row.originalPath,
                  onOpen: () => _openDetail(row),
                  onToggleFavorite: () => _toggleFavorite(row),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
