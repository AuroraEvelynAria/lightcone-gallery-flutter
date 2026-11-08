import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'artist_avatar_view.dart';
import 'artist_screen.dart';
import 'filtered_artworks_screen.dart';

/// 分类：画师 / 标签两个维度，按作品数排序。点进去是筛选后的作品瀑布流。
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<ArtistCount> _artists = const [];
  List<TagCount> _tags = const [];
  List<TagGalleryRow> _galleries = const [];
  int _aiCount = 0;
  bool _loading = true;
  int _tab = 0;
  int _lastVersion = 0;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _lastVersion = widget.state.dataVersion;
    widget.state.addListener(_onStateChanged);
    _load();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_lastVersion != widget.state.dataVersion) {
      _lastVersion = widget.state.dataVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final repo = widget.state.repo;
    final artists = await repo.artistCounts();
    final tags = await repo.tagCounts();
    final galleries = await repo.tagGalleries();
    final aiCount = await repo.aiArtworkCount();
    if (!mounted) return;
    setState(() {
      _artists = artists;
      _tags = tags;
      _galleries = galleries;
      _aiCount = aiCount;
      _loading = false;
    });
  }

  /// 内存内过滤：标签几千个时，靠搜索而不是靠翻。
  List<ArtistCount> get _visibleArtists {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _artists;
    return _artists
        .where((a) => a.name.toLowerCase().contains(q) || a.uid.contains(q))
        .toList();
  }

  List<TagCount> get _visibleTags {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _tags;
    return _tags.where((t) => t.tag.toLowerCase().contains(q)).toList();
  }

  /// 合成的「AI生成」标签：空搜索或搜 AI 时置顶，别的时候不占位置。
  bool get _showAi {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || 'ai生成'.contains(q) || 'ai'.contains(q);
  }

  /// 画廊按名字过滤（桌面存的组合，数量一般不多）。
  List<TagGalleryRow> get _visibleGalleries {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _galleries;
    return _galleries
        .where((g) => g.name.toLowerCase().contains(q) ||
            g.tags.any((t) => t.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final artists = _visibleArtists;
    final tags = _visibleTags;
    final galleries = _visibleGalleries;
    final matching = _query.trim().isNotEmpty;
    return Column(
      children: [
        // 标签几千个，翻是翻不过来的：搜索框直接过滤当前维度
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: switch (_tab) {
                0 => '搜索画师（名字或 UID）',
                1 => '搜索标签',
                _ => '搜索画廊',
              },
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: Text('画师 ${_artists.length}'),
                selected: _tab == 0,
                onSelected: (_) => setState(() => _tab = 0),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('标签 ${_tags.length}'),
                selected: _tab == 1,
                onSelected: (_) => setState(() => _tab = 1),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('画廊 ${_galleries.length}'),
                selected: _tab == 2,
                onSelected: (_) => setState(() => _tab = 2),
              ),
              if (matching) ...[
                const Spacer(),
                Text(
                  '匹配 ${switch (_tab) {
                    0 => artists.length,
                    1 => tags.length,
                    _ => galleries.length,
                  }}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _buildBody(artists, tags, galleries)),
      ],
    );
  }

  Widget _buildBody(
    List<ArtistCount> artists,
    List<TagCount> tags,
    List<TagGalleryRow> galleries,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    switch (_tab) {
      case 0:
        if (artists.isEmpty) return const Center(child: Text('没有匹配的画师'));
        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ListTile(
              // 只显示批量补好的头像（fetch=false）：一屏几十行不能逐行联网
              leading: ArtistAvatarView(
                // dataVersion 变了就换 key：补完头像后不用重启/切 tab
                key: ValueKey('avatar-${artist.uid}-${widget.state.dataVersion}'),
                state: widget.state,
                uid: artist.uid,
                name: artist.name,
                radius: 18,
                fetch: false,
              ),
              title: Text(artist.name),
              subtitle: Text(artist.uid),
              trailing: Text('${artist.count} 张'),
              onTap: () => _openArtist(context, artist),
            );
          },
        );
      case 1:
        // 原始 AI 标签（AI生成 / AIイラスト / ai…）都被合成标签收编，
        // 避免同一个意思在列表里出现七八次。
        final visible = tags
            .where((t) => !looksLikeAiTag(t.tag))
            .toList(growable: false);
        final showAi = _showAi;
        if (visible.isEmpty && !showAi) {
          return const Center(child: Text('没有匹配的标签'));
        }
        return ListView.builder(
          itemCount: visible.length + (showAi ? 1 : 0),
          itemBuilder: (context, index) {
            if (showAi && index == 0) {
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'AI生成',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: const Text('只看 AI 生成的作品'),
                subtitle: const Text('Pixiv AI 标记 / AI 标签汇总'),
                trailing: Text('$_aiCount 张'),
                onTap: () => _openFiltered(
                  context,
                  title: 'AI生成',
                  aiOnly: true,
                ),
              );
            }
            final tag = visible[showAi ? index - 1 : index];
            return ListTile(
              title: Text(tag.tag),
              trailing: Text('${tag.count} 张'),
              onTap: () => _openFiltered(
                context,
                title: '#${tag.tag}',
                tags: [tag.tag],
              ),
            );
          },
        );
      default:
        if (galleries.isEmpty) {
          return const Center(
            child: Text('还没有标签画廊\n在桌面端建好画廊后，这里会同步显示'),
          );
        }
        return ListView.builder(
          itemCount: galleries.length,
          itemBuilder: (context, index) {
            final gallery = galleries[index];
            return ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(gallery.name),
              subtitle: Text(
                gallery.tags.isEmpty ? '空画廊' : gallery.tags.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: gallery.rating >= 0 ? Text('≥${gallery.rating}★') : null,
              onTap: () => _openFiltered(
                context,
                title: gallery.name,
                tags: gallery.tags,
              ),
            );
          },
        );
    }
  }

  void _openFiltered(
    BuildContext context, {
    required String title,
    String? artistUid,
    List<String> tags = const [],
    bool aiOnly = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilteredArtworksScreen(
          state: widget.state,
          title: title,
          artistUid: artistUid,
          tags: tags,
          aiOnly: aiOnly,
        ),
      ),
    );
  }

  /// 画师走画师页（有汇总头部），不再进裸筛选页。
  void _openArtist(BuildContext context, ArtistCount artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistScreen(
          state: widget.state,
          uid: artist.uid,
          initialName: artist.name,
        ),
      ),
    );
  }
}
