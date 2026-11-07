import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/thumbnail_provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artwork_card.dart';
import 'artwork_detail_screen.dart';
import 'blur_thumb.dart';
import 'page_badge.dart';
import 'viewer_screen.dart';

/// 全局检索：作品按 PID / 标题 / 画师 / 标签，图片按文件名。
/// 输入防抖 300ms —— 跟手又不打爆 SQL。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<ArtworkRow> _artworks = const [];
  List<ImageRow> _images = const [];
  bool _searching = false;
  int _tab = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _query = '';
        _artworks = const [];
        _images = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _searching = true;
    });
    final repo = widget.state.repo;
    final results = await Future.wait([
      repo.searchArtworks(query),
      repo.searchImages(query),
    ]);
    if (!mounted || _query != query) return; // 输入已变：丢弃过期响应
    setState(() {
      _artworks = results[0] as List<ArtworkRow>;
      _images = results[1] as List<ImageRow>;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'PID / 标题 / 画师 / 标签 / 文件名',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        // 双 chip 切换结果域（不用 TabBar：它要求 TabController，这里状态自己管）
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilterChip(
                label: Text('作品${_artworks.isEmpty ? '' : ' ${_artworks.length}'}'),
                selected: _tab == 0,
                onSelected: (_) => setState(() => _tab = 0),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('图片${_images.isEmpty ? '' : ' ${_images.length}'}'),
                selected: _tab == 1,
                onSelected: (_) => setState(() => _tab = 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: _searching
              ? const Center(child: Text('搜索中…'))
              : _query.isEmpty
                  ? const Center(
                      child: Text(
                        '输入关键词\n作品按 PID / 标题 / 画师 / 标签匹配，图片按文件名匹配',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _tab == 0
                      ? _artworkResults()
                      : _imageResults(),
        ),
      ],
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

  void _openArtwork(ArtworkRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtworkDetailScreen(
          state: widget.state,
          pid: row.pid,
          initialPage: row.page,
          heroTag: 'search-${row.id}',
          onFavoriteChanged: (favorite) {
            if (!mounted) return;
            final at = _artworks.indexWhere((r) => r.id == row.id);
            if (at >= 0) {
              setState(() => _artworks[at] = _artworks[at].copyWith(favorite: favorite));
            }
          },
        ),
      ),
    );
  }

  Future<void> _toggleArtworkFavorite(ArtworkRow row) async {
    final at = _artworks.indexWhere((r) => r.id == row.id);
    if (at < 0) return;
    final next = !row.favorite;
    setState(() => _artworks[at] = row.copyWith(favorite: next));
    final updated = await widget.state.repo.setPidFavorite(row.pid, next);
    if (!mounted || updated > 0) return;
    final back = _artworks.indexWhere((r) => r.id == row.id);
    if (back >= 0) {
      setState(() => _artworks[back] = _artworks[back].copyWith(favorite: !next));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这张不在图库里，收藏只对图库图片生效')),
    );
  }

  Widget _artworkResults() {
    if (_artworks.isEmpty) return const Center(child: Text('作品没有匹配结果'));
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferred = AppSettingsScope.of(context).gridColumns;
        final columns = preferred > 0
            ? preferred
            : (constraints.maxWidth / 120).round().clamp(2, 6);
        final media = MediaQuery.of(context);
        final cellPx = media.size.width * media.devicePixelRatio / columns;
        final thumbSize = (cellPx * 1.6).round().clamp(320, 1024);
        return MasonryGridView.count(
          padding: const EdgeInsets.all(8),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: _artworks.length,
          itemBuilder: (context, index) {
            final row = _artworks[index];
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
              heroTag: 'search-${row.id}',
              onTap: () => _openArtwork(row),
              onFavorite: () => _toggleArtworkFavorite(row),
            );
          },
        );
      },
    );
  }

  Widget _imageResults() {
    if (_images.isEmpty) return const Center(child: Text('图片没有匹配结果'));
    final media = MediaQuery.of(context);
    final thumbSize = (media.size.width * media.devicePixelRatio / 3).round().clamp(200, 640);
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final row = _images[index];
        return GestureDetector(
          onTap: () {
            // 图库按作品归组后，图片结果也进作品详情（长图 + 单张）
            final parsed = row.pid == null ? null : parsePid(row.filename);
            if (parsed != null) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtworkDetailScreen(
                    state: widget.state,
                    pid: parsed.$1,
                    initialPage: parsed.$2,
                  ),
                ),
              );
              return;
            }
            final items = [
              ViewerItem(
                path: row.path,
                title: row.filename,
                aspectRatio: (row.width != null &&
                        row.height != null &&
                        row.height! > 0)
                    ? row.width! / row.height!
                    : 0,
              ),
            ];
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ViewerScreen(items: items, initialIndex: 0),
              ),
            );
          },
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
        );
      },
    );
  }
}
