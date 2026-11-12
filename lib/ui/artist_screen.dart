import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/models.dart';
import '../media/media_channel.dart';
import '../media/thumbnail_provider.dart';
import '../pixiv/artist_artworks.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'artist_avatar_view.dart';
import 'artwork_card.dart';
import 'artwork_detail_screen.dart';
import 'desktop/artwork_menu.dart';
import 'filtered_artworks_screen.dart';

/// 画师页：头部是本地汇总（头像 / 名字 / 作品数 / 页数 / 收藏 / 占用 /
/// 上传跨度 / 常用标签），下面是这个画师的作品瀑布流。
///
/// 图源仍然只认本机索引（pixez 下载到 `Pictures/pixez` 的那些文件）——
/// 线上只拉一份 PID 清单（`/ajax/user/{uid}/profile/all`）用来对照缺口：
/// 「本机 17 / 线上 123」，缺的排成占位卡，点一下去 Pixiv 或 pixez 下载。
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.state,
    required this.uid,
    this.initialName,
  });

  final AppState state;
  final String uid;

  /// 从列表点进来时已知的名字：头部先用它渲染，省一次空白。
  final String? initialName;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  static const _pageSize = 120;
  static const _gapPage = 120;

  final _rows = <ArtworkRow>[];
  final _controller = ScrollController();
  ArtistProfile? _profile;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  ArtistArtworks? _online;
  List<String> _missing = const [];
  bool _loadingOnline = false;
  String? _onlineError;
  bool _gapOnly = false;
  int _gapVisible = _gapPage;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 900) {
        _loadMore();
        if (_gapOnly) _moreGap();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await widget.state.repo.artistProfile(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
    await _loadMore();
    unawaited(_loadOnline());
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final page = await widget.state.repo.artworksPage(
      artistUid: widget.uid,
      offset: _rows.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _rows.addAll(page);
      _loadingMore = false;
      _hasMore = page.length >= _pageSize;
    });
  }

  void _moreGap() {
    if (_gapVisible >= _missing.length) return;
    setState(() => _gapVisible += _gapPage);
  }

  /// 拉线上 PID 清单，与本机对照出缺口。失败就只显示本机的部分。
  Future<void> _loadOnline({bool force = false}) async {
    if (_loadingOnline) return;
    setState(() {
      _loadingOnline = true;
      if (force) _onlineError = null;
    });
    final online = await ArtistArtworkStore.ensure(
      widget.state.repo,
      widget.uid,
      force: force,
    );
    if (!mounted) return;
    if (online == null) {
      setState(() {
        _loadingOnline = false;
        _onlineError = '拉不到线上清单（检查代理 / 网络）';
      });
      return;
    }
    final existing = await widget.state.repo.existingPids(online.pids);
    if (!mounted) return;
    setState(() {
      _online = online;
      _missing = [
        for (final pid in online.pids)
          if (!existing.contains(pid)) pid,
      ];
      _gapVisible = _gapPage;
      _loadingOnline = false;
      _onlineError = null;
    });
  }

  void _openDetail(ArtworkRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtworkDetailScreen(
          state: widget.state,
          pid: row.pid,
          initialPage: row.page,
          heroTag: 'artist-${row.id}',
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

  Future<void> _toggleFavorite(ArtworkRow row) async {
    final at = _rows.indexWhere((r) => r.id == row.id);
    if (at < 0) return;
    final next = !row.favorite;
    setState(() => _rows[at] = row.copyWith(favorite: next));
    final updated = await widget.state.repo.setPidFavorite(row.pid, next);
    if (!mounted || updated > 0) return;
    final back = _rows.indexWhere((r) => r.id == row.id);
    if (back >= 0) {
      setState(() => _rows[back] = _rows[back].copyWith(favorite: !next));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这张不在图库里，收藏只对图库图片生效')),
    );
  }

  Future<void> _openUrl(String url) async {
    final ok = await MediaChannel.openUrl(url);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有可以打开链接的应用')),
    );
  }

  Future<void> _openPixiv() =>
      _openUrl('https://www.pixiv.net/users/${widget.uid}');

  Future<void> _openPixivArtwork(String pid) =>
      _openUrl('https://www.pixiv.net/artworks/$pid');

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name =
        profile?.displayName ?? widget.initialName ?? 'UID ${widget.uid}';
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: _loadingOnline
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            tooltip: '刷新线上作品清单',
            onPressed: _loadingOnline
                ? null
                : () => _loadOnline(force: true),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '在 Pixiv 打开画师页',
            onPressed: _openPixiv,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final preferred = AppSettingsScope.of(context).gridColumns;
                final columns = preferred > 0
                    ? preferred
                    : (constraints.maxWidth / 120).round().clamp(2, 6);
                final media = MediaQuery.of(context);
                final cellPx = media.size.width * media.devicePixelRatio / columns;
                final thumbSize = (cellPx * 1.6).round().clamp(320, 1024);
                return CustomScrollView(
                  controller: _controller,
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(profile)),
                    if (_gapOnly)
                      _gapSliver(context, columns)
                    else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      sliver: SliverMasonryGrid.count(
                        crossAxisCount: columns,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childCount: _rows.length,
                        itemBuilder: (context, index) => _tile(
                          context,
                          _rows[index],
                          thumbSize,
                          columns,
                          cellPx,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildHeader(ArtistProfile? profile) {
    final theme = Theme.of(context);
    final name =
        profile?.displayName ?? widget.initialName ?? 'UID ${widget.uid}';
    final online = _online;
    final missingCount = _missing.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArtistAvatarView(
                state: widget.state,
                uid: widget.uid,
                name: name,
                radius: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile?.account == null
                          ? 'UID ${widget.uid}'
                          : 'UID ${widget.uid} · @${profile!.account}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: '作品 ${profile.artworks}'),
                _Pill(label: '页 ${profile.pages}'),
                if (profile.favorites > 0)
                  _Pill(label: '收藏 ${profile.favorites}'),
                _Pill(label: '占用 ${formatBytes(profile.bytes)}'),
                if (profile.firstDay != null)
                  _Pill(
                    label: profile.firstDay == profile.lastDay
                        ? profile.firstDay!
                        : '${profile.firstDay} ~ ${profile.lastDay}',
                  ),
                if (online != null)
                  _Pill(
                    label: '本机 ${profile.artworks} / 线上 ${online.pids.length}',
                  ),
              ],
            ),
            if (_onlineError != null) ...[
              const SizedBox(height: 8),
              Text(_onlineError!, style: theme.textTheme.labelSmall),
            ],
            if (online != null && missingCount > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  FilterChip(
                    label: Text(_gapOnly ? '看全部' : '只看缺的 $missingCount'),
                    selected: _gapOnly,
                    onSelected: (_) => setState(() => _gapOnly = !_gapOnly),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '缺的用 pixez 下载后重扫就会补上',
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (profile.topTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in profile.topTags)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tag),
                      onPressed: () => _openTag(tag),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _gapSliver(BuildContext context, int columns) {
    if (_missing.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('线上作品本机都有了')),
        ),
      );
    }
    final visible = _missing.length < _gapVisible
        ? _missing.length
        : _gapVisible;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 24),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: columns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childCount: visible + (_missing.length > visible ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible) {
            return _gapMoreTile(_missing.length - visible);
          }
          return _missingTile(context, _missing[index]);
        },
      ),
    );
  }

  Widget _missingTile(BuildContext context, String pid) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _openPixivArtwork(pid),
      child: AspectRatio(
        aspectRatio: 0.75,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_download_outlined,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 6),
              Text(pid, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                '本机没有 · 去 Pixiv',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gapMoreTile(int left) => GestureDetector(
        onTap: _moreGap,
        child: AspectRatio(
          aspectRatio: 0.75,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Center(
              child: Text(
                '还有 $left 个\n点这里继续',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      );

  void _openTag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilteredArtworksScreen(
          state: widget.state,
          title: '#$tag',
          tags: [tag],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    ArtworkRow row,
    int thumbSize,
    int columns,
    double cellPx,
  ) {
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
      heroTag: 'artist-${row.id}',
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
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
