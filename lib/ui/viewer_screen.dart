import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../media/media_channel.dart';

/// 检视条目：路径 + 标题（图库与作品库共用同一个检视器）。
class ViewerItem {
  const ViewerItem({
    required this.path,
    required this.title,
    this.aspectRatio = 0,
  });

  final String path;
  final String title;

  /// 宽 / 高；0 = 未知。双击放大时用来算「铺满屏高」的倍率。
  final double aspectRatio;
}

/// 全屏检视器：左右翻页（PageView）+ 双指缩放（InteractiveViewer）。
///
/// 解码分两级（见 [_ViewerImage]）：先按屏宽解一张快图，当前页空闲后再补
/// 一张原图。网格里永远不碰大图 —— 这里也只在需要时才放大分辨率。
///
/// 顶栏带分享与「设为壁纸」，直接对当前这张图操作。
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<ViewerItem> items;
  final int initialIndex;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// 当前页是否处于放大状态。放大后要禁止 PageView 抢横向拖动，
  /// 否则手指想平移图片，页面会翻走。
  bool _zoomed = false;

  /// 当前按在屏幕上的手指数。第二根手指一落下就先锁住 PageView：
  /// 真机双指捏合时第一根手指往往已经被 PageView 的横向拖动跟踪，
  /// 等 scale 超过 1 再禁就晚了。
  int _pointers = 0;

  /// PageView 是否因为多指而被锁住。单独存一份是为了「只有锁的开关真的变了
  /// 才重建」—— 见 [_syncPointerLock]。
  bool _multiTouch = false;

  /// 每页一个变换控制器：双击在「整张」和「铺满屏高」之间切换。
  final _transforms = <int, TransformationController>{};

  /// 双击缩放走 240ms 的矩阵补间，别再瞬间跳过去。
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Animation<Matrix4>? _zoomTween;
  int? _zoomIndex;

  @override
  void initState() {
    super.initState();
    _zoomAnimation.addListener(() {
      final tween = _zoomTween;
      final index = _zoomIndex;
      if (tween != null && index != null) {
        _transformFor(index).value = tween.value;
      }
    });
  }

  TransformationController _transformFor(int index) => _transforms.putIfAbsent(
    index,
    () => TransformationController()..addListener(_onZoomChanged),
  );

  void _onZoomChanged() {
    final zoomed = _transformFor(_index).value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed && mounted) {
      setState(() => _zoomed = zoomed);
    }
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// 以屏幕中心为锚点缩放，双击切回整张；矩阵用补间动画过渡。
  void _toggleZoom(int index, Size screen) {
    final controller = _transformFor(index);
    final current = controller.value.clone();
    final zoomed = current.getMaxScaleOnAxis() > 1.01;
    final target = zoomed
        ? 1.0
        : fillHeightScale(widget.items[index].aspectRatio, screen);
    final center = Offset(screen.width / 2, screen.height / 2);
    // 绕屏幕中心缩放：x' = s·x + c(1-s)，直接写矩阵，避开已废弃的
    // Matrix4.translate / scale。
    final targetMatrix = Matrix4.identity()
      ..setEntry(0, 0, target)
      ..setEntry(1, 1, target)
      ..setEntry(0, 3, center.dx * (1 - target))
      ..setEntry(1, 3, center.dy * (1 - target));
    _zoomAnimation.stop();
    _zoomTween = Matrix4Tween(begin: current, end: targetMatrix).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
    );
    _zoomIndex = index;
    _zoomAnimation.forward(from: 0);
  }

  Future<void> _share({bool asFile = false}) async {
    final item = widget.items[_index];
    final ok = await MediaChannel.shareImages(
      [item.path],
      text: item.title,
      asFile: asFile,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('分享失败：没有可用的应用或文件不存在')));
  }

  Future<void> _saveToGallery() async {
    final item = widget.items[_index];
    final name = p.basename(item.path);
    final ok = await MediaChannel.saveToGallery(item.path, name: name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (Platform.isWindows
                    ? '已保存到 Pictures\\LightCone'
                    : '已保存到相册 Pictures/LightCone')
              : '保存失败',
        ),
      ),
    );
  }

  Future<void> _setWallpaper() async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('设为壁纸'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'home'),
            child: const Text('主屏幕'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'lock'),
            child: const Text('锁屏'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'both'),
            child: const Text('主屏幕 + 锁屏'),
          ),
        ],
      ),
    );
    if (target == null) return;
    final ok = await MediaChannel.setWallpaper(
      widget.items[_index].path,
      target: target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? '已设为壁纸' : '设置壁纸失败')));
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.items.length) return;
    _zoomAnimation.stop();
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPointerDown(PointerDownEvent _) {
    _pointers++;
    _syncPointerLock();
  }

  void _onPointerUp(PointerUpEvent _) {
    if (_pointers > 0) _pointers--;
    _syncPointerLock();
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (_pointers > 0) _pointers--;
    _syncPointerLock();
  }

  /// 只有「是否锁住 PageView」真的变了才 setState。
  ///
  /// 原先每次 pointerDown/Up 都 setState，等于把整棵 PageView 连同它的
  /// ScrollPhysics 一起换掉；`Scrollable` 一发现 physics 变了就会重建
  /// ScrollPosition，而这一下正好落在手势开始的那一帧上，手感就发涩。
  void _syncPointerLock() {
    final locked = _pointers > 1;
    if (locked != _multiTouch && mounted) {
      setState(() => _multiTouch = locked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goToPage(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goToPage(_index + 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black45,
            foregroundColor: Colors.white,
            actions: [
              if (Platform.isWindows)
                IconButton(
                  icon: const Icon(Icons.folder_open_outlined),
                  tooltip: '在资源管理器中显示',
                  onPressed: () => MediaChannel.revealInExplorer([
                    widget.items[_index].path,
                  ]),
                )
              else
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: '分享',
                  onPressed: _share,
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'wallpaper':
                      _setWallpaper();
                    case 'share-file':
                      _share(asFile: true);
                    case 'save':
                      _saveToGallery();
                    case 'reveal':
                      MediaChannel.revealInExplorer([
                        widget.items[_index].path,
                      ]);
                  }
                },
                itemBuilder: (_) => [
                  if (!Platform.isWindows) ...[
                    const PopupMenuItem(
                      value: 'wallpaper',
                      child: Text('设为壁纸…'),
                    ),
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
                      Platform.isWindows ? '保存原图到 Pictures' : '保存原图到相册',
                    ),
                  ),
                ],
              ),
            ],
            title: Text(
              '${_index + 1} / ${widget.items.length} · ${widget.items[_index].title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          body: Stack(
            children: [
              Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: PageView.builder(
                  controller: _controller,
                  // 放大后 PageView 不抢横向手势：左右滑是平移图片，不是翻页。
                  // 第二根手指落下时（_multiTouch）也先锁住，给捏合让路。
                  physics: (_zoomed || _multiTouch)
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  // 预建左右两页：翻过去时缩略图已经在解码路上了，不会白一屏。
                  allowImplicitScrolling: true,
                  itemCount: widget.items.length,
                  onPageChanged: (index) {
                    _zoomAnimation.stop();
                    setState(() {
                      _index = index;
                      _zoomed =
                          _transformFor(index).value.getMaxScaleOnAxis() > 1.01;
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final screen = MediaQuery.sizeOf(context);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 横图整张看的时候只有一条，双击铺满屏高再左右拖
                      onDoubleTap: () => _toggleZoom(index, screen),
                      child: InteractiveViewer(
                        transformationController: _transformFor(index),
                        minScale: 1,
                        maxScale: 10,
                        // 默认 200：要滑很长一段才放大。100 跟手得多。
                        // Windows 滚轮一个 notch 是 ~120px，100 会一次放 3 倍；
                        // 桌面用 500，约 1.27 倍/格。
                        scaleFactor: Platform.isWindows ? 500 : 100,
                        clipBehavior: Clip.none,
                        // 只在真正的双指手势开始时停掉双击补间；单击/双击的第二下
                        // 也是 pointerCount == 1，不能在这里停，否则动画刚启动就没了。
                        onInteractionStart: (details) {
                          if (details.pointerCount > 1) _zoomAnimation.stop();
                        },
                        child: Center(
                          child: _ViewerImage(
                            key: ValueKey(item.path),
                            item: item,
                            active: index == _index,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 只有横图需要提示：竖图本来就没有「放大到屏高」的必要
              if (widget.items[_index].aspectRatio > 1.4)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                  child: const IgnorePointer(
                    child: Center(child: _ViewerHint(text: '双击切换大小 · 拖动查看')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 检视器里的一张图，分两级解码。
///
/// 1. **快图**：先按「屏宽 × DPR」解一张 —— 手机上和详情页 `PageStage` 用的
///    是同一个 `ResizeImage` key，所以从详情页点进来能直接命中已经解好的那张，
///    白屏时间几乎为零。（桌面开着 380px 信息栏时两边宽度不同，命中不了，
///    但桌面内存不紧张，这一层就只剩「首帧更快」的好处。）
/// 2. **原图**：当前页空闲下来之后，再在后台解一张（宽度受 [_detailCap]
///    约束），解完无缝换上，供放大到 2× 以上时看细节。
///
/// 为什么非分级不可：主人的原图有 4488×6000 这种量级，直接解出来是
/// **103MB 的 RGBA**；光把这块纹理上传给 GPU 就能吃掉好几帧，而快图
/// 同尺寸只要 ~8MB。卡顿就卡在这条路上。
///
/// 两级都用 `FilterQuality.medium`（trilinear）：大图缩小时必须走 mipmap，
/// 否则每个屏幕像素都要在上百 MB 的纹理里乱采样，显存带宽直接打满。
class _ViewerImage extends StatefulWidget {
  const _ViewerImage({super.key, required this.item, required this.active});

  final ViewerItem item;

  /// 是否是当前页。只有当前页值得多花内存去解原图。
  final bool active;

  @override
  State<_ViewerImage> createState() => _ViewerImageState();
}

class _ViewerImageState extends State<_ViewerImage> {
  /// 快图宽度（物理像素）。屏宽/DPR 变了（转向、改缩放）就重来一遍。
  int _baseWidth = 0;

  late ImageProvider _provider;

  /// 换尺寸或换页时递增，用来作废还在路上的后台任务。
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = _baseWidthFor(MediaQuery.of(context));
    if (target == _baseWidth) return;
    _baseWidth = target;
    _provider = ResizeImage(FileImage(File(widget.item.path)), width: target);
    _scheduleDetail();
  }

  @override
  void didUpdateWidget(_ViewerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻到这一页了，才值得去解原图。
    if (!oldWidget.active && widget.active) _scheduleDetail();
  }

  /// 快图宽度 = 屏宽 × DPR，与 `PageStage` 的解码宽度逐像素一致 —— key 相同
  /// 才能命中详情页的缓存。下限 512 防极端小窗，上限 4096 防桌面超宽屏。
  static int _baseWidthFor(MediaQueryData media) {
    final wanted = (media.size.width * media.devicePixelRatio).round();
    if (wanted < 512) return 512;
    return wanted > 4096 ? 4096 : wanted;
  }

  /// 原图解码宽度上限。手机上 4096 宽的长图约 90MB RGBA，和改动之前持平
  /// 而不再失控（未知边长的巨图会被压到这个尺寸）；桌面显存宽裕，放到 8192。
  static int get _detailCap => Platform.isWindows ? 8192 : 4096;

  /// 空闲 600ms 后再去解原图：太快会跟首帧、以及用户的第一个手势抢解码。
  void _scheduleDetail() {
    final generation = ++_generation;
    if (!widget.active) return;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || generation != _generation) return;
      _loadDetail(generation);
    });
  }

  Future<void> _loadDetail(int generation) async {
    final path = widget.item.path;
    final intrinsic = await _intrinsicWidth(path);
    if (!mounted || generation != _generation) return;
    var width = intrinsic <= 0 ? _detailCap : intrinsic;
    if (width > _detailCap) width = _detailCap;
    // 原图只比快图宽不到 1.2 倍时换上去也看不出差别，不值那份内存。
    if (width < _baseWidth * 1.2) return;
    final detail = ResizeImage(FileImage(File(path)), width: width);
    try {
      await precacheImage(detail, context, onError: (_, _) {});
    } catch (_) {
      return; // 原图解不开就继续用快图，不打扰用户
    }
    if (!mounted || generation != _generation || !widget.active) return;
    // gaplessPlayback 会一直显示旧帧，直到新的一帧就绪 —— 换图不闪。
    setState(() => _provider = detail);
  }

  /// 只读文件头拿原始宽度，不解像素（`FileImage` 内部也是同一个 buffer）。
  /// 失败返回 0，调用方按「宽得不知道」处理。
  static Future<int> _intrinsicWidth(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return descriptor.width;
    } catch (_) {
      return 0;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Image(
        image: _provider,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text('图片读取失败', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

/// 双击「铺满屏高」的倍率：横图按宽度显示后，要放大多少才占满屏高。
/// 竖图本来就接近屏高，给 2× 的手感；比例未知也按 2×。
@visibleForTesting
double fillHeightScale(double aspectRatio, Size screen) {
  if (aspectRatio <= 0 || screen.height <= 0) return 2;
  final screenAspect = screen.width / screen.height;
  final displayedHeight = aspectRatio >= screenAspect
      ? screen.width / aspectRatio
      : screen.height;
  return (screen.height / displayedHeight).clamp(2.0, 10.0);
}

class _ViewerHint extends StatelessWidget {
  const _ViewerHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

// ── 进出场动画 ────────────────────────────────────────────────────────
//
// 三个入口（图库图片、搜索结果、详情缩略条）都走 [viewerRoute]，
// 过场保持一致：整页淡入 + 从 0.92 放大到 1，退出时原路退回。
//
// 为什么不用 Hero 飞回来源缩略图：检视器内部是 PageView，退出时用户
// 可能已经翻到别的图、或放大过；这时"飞回最初点开的那张卡"会指错对象。
// 整页缩放在翻页、缩放、甚至是失败占位图上都成立，不会有语义错乱。
//
// 时长与起始缩放抽成常量：调手感时只动这三个数字。

/// 点进检视器的时长。
const Duration kViewerEnterDuration = Duration(milliseconds: 260);

/// 退出检视器的时长。比进入略快 —— 退出是「回到刚才」，拖久了会烦。
const Duration kViewerExitDuration = Duration(milliseconds: 200);

/// 进场起始缩放。0.92 是「轻轻推近」，再小就像从远处飞过来，太重。
const double kViewerEnterScale = 0.92;

/// 过渡层的 Key：给测试精确定位用，避免撞上 Material 自己的页面过渡。
const String viewerTransitionFadeKey = 'viewer-route-fade';
const String viewerTransitionScaleKey = 'viewer-route-scale';

/// 检视器路由：淡入 + 轻微放大；[Navigator.pop] 时自动反向播放。
Route<void> viewerRoute({
  required List<ViewerItem> items,
  required int initialIndex,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: kViewerEnterDuration,
    reverseTransitionDuration: kViewerExitDuration,
    pageBuilder: (_, _, _) =>
        ViewerScreen(items: items, initialIndex: initialIndex),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // 用 drive 而不是 CurvedAnimation：后者需要 dispose，在
      // transitionsBuilder 里每次 build 建一个会泄漏。
      const curve = Curves.easeOutCubic;
      return FadeTransition(
        // Key 只为测试能精确拿到这两层过渡：树里还有 Material 自己的
        // 页面过渡，按类型找会撞上。
        key: const ValueKey(viewerTransitionFadeKey),
        opacity: animation.drive(CurveTween(curve: curve)),
        child: ScaleTransition(
          key: const ValueKey(viewerTransitionScaleKey),
          scale: animation.drive(
            Tween<double>(
              begin: kViewerEnterScale,
              end: 1,
            ).chain(CurveTween(curve: curve)),
          ),
          child: child,
        ),
      );
    },
  );
}
