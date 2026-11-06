import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_detail_screen.dart';
import 'blur_thumb.dart';
import 'page_badge.dart';

/// 画师 / 标签筛选后的作品页（复用作品库的瀑布流）。
class FilteredArtworksScreen extends StatefulWidget {
  const FilteredArtworksScreen({
    super.key,
    required this.state,
    required this.title,
    this.artistUid,
    this.tags = const [],
  });

  final AppState state;
  final String title;
  final String? artistUid;
  final List<String> tags;

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
        ),
      ),
    );
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
          final thumbSize =
              (media.size.width * media.devicePixelRatio / columns).round().clamp(200, 640);
          return MasonryGridView.count(
            controller: _controller,
            padding: const EdgeInsets.all(6),
            crossAxisCount: columns,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              return GestureDetector(
                onTap: () => _openDetail(row),
                child: Hero(
                  tag: 'art-${row.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: row.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          blurR18IfNeeded(
                            context,
                            row.xRestrict ?? 0,
                            Image(
                              image: imageProviderFor(row.mediaId, row.originalPath, size: thumbSize),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                          if (row.pageTotal > 1)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: PageBadge(count: row.pageTotal),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
