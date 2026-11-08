import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../media/media_channel.dart';
import '../state/app_state.dart';
import 'artist_avatar_view.dart';
import 'artist_screen.dart';
import 'filtered_artworks_screen.dart';
import 'page_stage.dart';
import 'viewer_screen.dart';

/// 作品详情页：pixez 的信息层级 —— 大图（可翻页）→ 标题 → 画师 → PID/页数/日期
/// → 标签（可点）→ 收藏 / 在 Pixiv 打开 / 移出作品库。
///
/// 图片只在当前页解码，并按屏宽 `cacheWidth` 缩采样；点图进全屏检视器才用原图。
class ArtworkDetailScreen extends StatefulWidget {
  const ArtworkDetailScreen({
    super.key,
    required this.state,
    required this.pid,
    this.initialPage = 0,
    this.initialArtworkId,
    this.heroTag,
    this.onFavoriteChanged,
  });

  final AppState state;
  final String pid;

  /// 作品内的页码（artworks.page），不是列表下标。
  final int initialPage;
  final int? initialArtworkId;

  /// 网格 → 详情页的 Hero 标记（与网格里那一格的 tag 一致）。
  final Object? heroTag;
  final ValueChanged<bool>? onFavoriteChanged;

  @override
  State<ArtworkDetailScreen> createState() => _ArtworkDetailScreenState();
}

class _ArtworkDetailScreenState extends State<ArtworkDetailScreen> {
  ArtworkDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _favorite = false;
  bool _busyFavorite = false;
  bool _busyRating = false;
  int _rating = 0;

  /// 竖排长图的滚动控制器。
  ScrollController? _scroll;
  int _initialIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.state.repo.artworkDetail(widget.pid);
      if (!mounted) return;
      final index = detail.pages.indexWhere(
        (p) => p.page == widget.initialPage,
      );
      setState(() {
        _detail = detail;
        _favorite = detail.favorite;
        _rating = detail.rating;
        _initialIndex = index < 0 ? 0 : index;
        _scroll = ScrollController();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openArtist(ArtworkDetail detail) {
    final uid = detail.artistUid;
    if (uid == null || uid.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistScreen(
          state: widget.state,
          uid: uid,
          initialName: detail.artistLabel,
        ),
      ),
    );
  }

  Future<void> _setRating(int star) async {
    if (_busyRating) return;
    final previous = _rating;
    final next = star == _rating ? 0 : star; // 再点同一颗星 = 清零
    setState(() {
      _rating = next;
      _busyRating = true;
    });
    final updated = await widget.state.repo.setPidRating(widget.pid, next);
    if (!mounted) return;
    setState(() {
      _busyRating = false;
      if (updated == 0) _rating = previous;
    });
    if (updated == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这张不在图库里，评分只对图库图片生效')));
    }
  }

  Future<void> _toggleFavorite() async {
    if (_busyFavorite) return;
    final previous = _favorite;
    final next = !_favorite;
    setState(() {
      _favorite = next;
      _busyFavorite = true;
    });
    final updated = await widget.state.repo.setPidFavorite(widget.pid, next);
    if (!mounted) return;
    setState(() {
      _busyFavorite = false;
      // 不在 pixez 图库里的作品没有 images 行，收藏落不了地
      if (updated == 0) _favorite = previous;
    });
    if (updated == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这张不在图库里，收藏只对图库图片生效')));
      return;
    }
    widget.onFavoriteChanged?.call(next);
  }

  Future<void> _openPixiv() async {
    final ok = await MediaChannel.openUrl(
      'https://www.pixiv.net/artworks/${widget.pid}',
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('没有可以打开链接的应用')));
  }

  /// 分享整个作品：多页会一次带上（ACTION_SEND_MULTIPLE）。
  Future<void> _shareAll(ArtworkDetail detail, {bool asFile = false}) async {
    final paths = detail.pages
        .map((page) => page.originalPath)
        .toList(growable: false);
    final ok = await MediaChannel.shareImages(
      paths,
      text: detail.displayTitle,
      asFile: asFile,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('分享失败：没有可用的应用或文件不存在')));
  }

  /// 把作品的每一页原图存进相册 Pictures/LightCone。
  Future<void> _saveToGallery(ArtworkDetail detail) async {
    var saved = 0;
    for (final page in detail.pages) {
      final name = p.basename(page.originalPath);
      if (await MediaChannel.saveToGallery(page.originalPath, name: name)) {
        saved++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == detail.pages.length
              ? (Platform.isWindows
                    ? '已保存 $saved 张到 Pictures\\LightCone'
                    : '已保存 $saved 张到相册 Pictures/LightCone')
              : '保存了 $saved / ${detail.pages.length} 张',
        ),
      ),
    );
  }

  Future<void> _setWallpaper(ArtworkDetail detail, String target) async {
    final ok = await MediaChannel.setWallpaper(
      detail.pages.first.originalPath,
      target: target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? '已设为壁纸' : '设置壁纸失败')));
  }

  Future<void> _copyPid() async {
    await Clipboard.setData(ClipboardData(text: widget.pid));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 PID ${widget.pid}')));
  }

  Future<void> _removeFromLibrary(ArtworkDetail detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出作品库？'),
        content: Text(
          'PID ${detail.pid} 的 ${detail.pages.length} 页都会移出（原图不会被删除），'
          '重扫也不会收回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.state.repo.removeArtworks(
      detail.pages.map((p) => p.id).toList(growable: false),
    );
    widget.state.bumpData();
    if (mounted) Navigator.of(context).pop();
  }

  void _openViewer(ArtworkDetail detail, int index) {
    final items = detail.pages
        .map(
          (p) => ViewerItem(
            path: p.originalPath,
            title: p.title?.isNotEmpty == true ? p.title! : 'PID ${p.pid}',
            aspectRatio: p.aspectRatio,
          ),
        )
        .toList(growable: false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(items: items, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      // 沉浸式：图片顶到状态栏，返回/菜单浮在图上（pixez 的做法）
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        // pixez 的详情顶栏只有图标浮在图上，没有标题和整条黑罩 —— 图优先
        flexibleSpace: const _TopScrim(),
        // 标题/画师在图片下方的信息区，顶栏不占视觉
        title: null,
        actions: [
          if (detail != null && detail.pages.isNotEmpty) ...[
            if (!Platform.isWindows)
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: '分享',
                onPressed: () => _shareAll(detail),
              ),
            if (Platform.isWindows)
              IconButton(
                icon: const Icon(Icons.folder_open_outlined),
                tooltip: '在资源管理器中显示',
                onPressed: () => MediaChannel.revealInExplorer(
                  detail.pages.map((page) => page.originalPath).toList(),
                ),
              ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'remove':
                    _removeFromLibrary(detail);
                  case 'wall-home':
                    _setWallpaper(detail, 'home');
                  case 'wall-lock':
                    _setWallpaper(detail, 'lock');
                  case 'wall-both':
                    _setWallpaper(detail, 'both');
                  case 'share-file':
                    _shareAll(detail, asFile: true);
                  case 'save':
                    _saveToGallery(detail);
                  case 'reveal':
                    MediaChannel.revealInExplorer(
                      detail.pages.map((page) => page.originalPath).toList(),
                    );
                }
              },
              itemBuilder: (_) => [
                if (!Platform.isWindows) ...[
                  const PopupMenuItem(
                    value: 'wall-home',
                    child: Text('设为壁纸（主屏）'),
                  ),
                  const PopupMenuItem(
                    value: 'wall-lock',
                    child: Text('设为壁纸（锁屏）'),
                  ),
                  const PopupMenuItem(
                    value: 'wall-both',
                    child: Text('设为壁纸（主屏 + 锁屏）'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'share-file',
                    child: Text('以文件分享（不压缩）'),
                  ),
                ],
                if (Platform.isWindows)
                  const PopupMenuItem(
                    value: 'reveal',
                    child: Text('在资源管理器中显示'),
                  ),
                PopupMenuItem(
                  value: 'save',
                  child: Text(
                    Platform.isWindows ? '保存全部原图到 Pictures' : '保存原图到相册',
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: Text('移出作品库')),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorBody(error: _error!)
          : detail == null
          ? const SizedBox.shrink()
          : (Platform.isWindows && detail.pages.isNotEmpty)
          ? Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        _buildStrip(detail, width: constraints.maxWidth),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    // 详情是沉浸式顶栏：右侧信息别钻到 AppBar 下面。
                    padding: EdgeInsets.only(
                      top:
                          MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          8,
                    ),
                    child: _buildInfo(detail),
                  ),
                ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    // 图片顶在最上面（主人要求）；标题/画师在顶栏一直可见，
                    // 完整信息在长图之后。
                    if (detail.pages.isEmpty)
                      SliverToBoxAdapter(
                        child: _MissingBody(onOpenPixiv: _openPixiv),
                      )
                    else
                      _buildStrip(detail),
                    SliverToBoxAdapter(child: _buildInfo(detail)),
                  ],
                ),
              ),
            ),
      // 长图可能几十页：动作放常驻底栏，滚到哪都能点（桌面放右侧信息栏）
      bottomNavigationBar:
          Platform.isWindows || detail == null || detail.pages.isEmpty
          ? null
          : Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busyFavorite ? null : _toggleFavorite,
                          icon: Icon(
                            _favorite ? Icons.favorite : Icons.favorite_border,
                          ),
                          label: Text(_favorite ? '已收藏' : '收藏'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openPixiv,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('在 Pixiv 打开'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  static const _stripGap = 2.0;

  /// 详情页的图片一律走这个 provider：与 `Image.file(cacheWidth:)` 内部的
  /// `ResizeImage(FileImage(...))` 完全一致 —— 只有 key 一致，缓存才会被命中。
  ImageProvider _pageProvider(ArtworkRow page, int cacheWidth) =>
      ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        FileImage(File(page.originalPath)),
      );

  /// 竖排长图（pixez 的「看的时候拼成长图」）：所有页按原始比例竖向拼接，
  /// 像一条长卷滚下来，不再横向翻页。点任意一页进单张检视器（左右滑）。
  ///
  /// 用 SliverList 而不是把 51 张全塞进 Column：只有可视区域附近才会构建、
  /// 解码，内存不会被整本画集撑爆。
  ///
  /// 横页的版面在 [PageStage] 里单独算：横图只按宽度铺会变成薄薄一条，
  /// 第一页还会整条钻到顶栏底下（点都点不到），所以横页给更高的舞台，
  /// 第一页再把状态栏 + 工具栏的高度让出来。
  Widget _buildStrip(ArtworkDetail detail, {double? width}) {
    final media = MediaQuery.of(context);
    final pageWidth = width ?? media.size.width;
    // 状态栏 + 工具栏 + 8dp 呼吸位：横图第一页从这下面开始
    final appBarBottom = media.padding.top + kToolbarHeight + 8;
    return SliverList.separated(
      itemCount: detail.pages.length,
      separatorBuilder: (_, _) => const SizedBox(height: _stripGap),
      itemBuilder: (context, index) {
        final page = detail.pages[index];
        return ArtworkPageTile(
          page: page,
          screenWidth: pageWidth,
          screenHeight: media.size.height,
          appBarBottom: appBarBottom,
          first: index == 0,
          providerFor: (cacheWidth) => _pageProvider(page, cacheWidth),
          onTap: () => _openViewer(detail, index),
          // 只让点进来的那一页参与 Hero，避免同一 PID 多页 tag 冲突
          heroTag: index == _initialIndex ? widget.heroTag : null,
          showR18: index == 0 && detail.xRestrict > 0,
        );
      },
    );
  }

  void _openAiFiltered() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilteredArtworksScreen(
          state: widget.state,
          title: 'AI生成',
          aiOnly: true,
        ),
      ),
    );
  }

  Widget _buildInfo(ArtworkDetail detail) {
    final theme = Theme.of(context);
    final artistUid = detail.artistUid;
    final ai = detail.isAiGenerated;
    final tags = ai
        ? detail.tags.where((t) => !looksLikeAiTag(t)).toList(growable: false)
        : detail.tags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.displayTitle,
            style: theme.textTheme.titleLarge?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          // 整行可点：头像 / 名字 → 画师页（作品汇总 + 常用标签）
          InkWell(
            onTap: artistUid == null ? null : () => _openArtist(detail),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  ArtistAvatarView(
                    state: widget.state,
                    uid: artistUid,
                    name: detail.artistLabel,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.artistLabel,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (artistUid != null)
                          Text(
                            'UID $artistUid · 画师页',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.tag,
                label: 'PID ${detail.pid}',
                onTap: _copyPid,
              ),
              _MetaChip(
                icon: Icons.photo_library_outlined,
                label: '${detail.pages.length} 页',
              ),
              if (detail.createDate != null && detail.createDate!.length >= 10)
                _MetaChip(
                  icon: Icons.cloud_upload_outlined,
                  label: '上传 ${detail.createDate!.substring(0, 10)}',
                ),
              // 保存时间单独一个：取自本地文件的 modified_at，不是 Pixiv 的日期
              if ((detail.savedAt ?? 0) > 0)
                _MetaChip(
                  icon: Icons.save_alt_outlined,
                  label: '保存 ${_formatDate(detail.savedAt!)}',
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 评分：一个作品一组，点同一颗星可以清零
          Row(
            children: [
              Text('评分', style: theme.textTheme.labelMedium),
              const SizedBox(width: 6),
              for (var star = 1; star <= 5; star++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  iconSize: 22,
                  color: star <= _rating
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  onPressed: _busyRating ? null : () => _setRating(star),
                ),
            ],
          ),
          if (ai || tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 合成标签放在首位：黑底白字，点它看全部 AI 生成作品
                if (ai)
                  ActionChip(
                    label: const Text('AI生成'),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: Colors.black,
                    side: BorderSide.none,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onPressed: _openAiFiltered,
                  ),
                for (final tag in tags)
                  ActionChip(
                    label: Text(tag),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FilteredArtworksScreen(
                            state: widget.state,
                            title: '#$tag',
                            tags: [tag],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          // 桌面：收藏 / 打开固定在右侧信息栏；手机：底部常驻栏。
          if (Platform.isWindows) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busyFavorite ? null : _toggleFavorite,
                icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
                label: Text(_favorite ? '已收藏' : '收藏'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openPixiv,
                icon: const Icon(Icons.open_in_new),
                label: const Text('在 Pixiv 打开'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// AppBar 背后的顶部渐变：只压很薄一层，保证白色图标在浅色图上可见，
/// 又不至于把短图整条盖黑（pixez 干脆没有，这里留一点可读性）。
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66000000), Color(0x00000000)],
            stops: [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 秒级时间戳 → YYYY-MM-DD（本地时区）。
String _formatDate(int seconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingBody extends StatelessWidget {
  const _MissingBody({required this.onOpenPixiv});

  final VoidCallback onOpenPixiv;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          const Icon(Icons.image_not_supported_outlined, size: 40),
          const SizedBox(height: 10),
          const Text('本机没有这个作品的文件'),
          const SizedBox(height: 6),
          Text(
            '可以先扫描一次，或在 Pixiv 上查看',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onOpenPixiv,
            child: const Text('在 Pixiv 打开'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text('读取失败：$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
