import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'state/app_settings.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/palettes.dart';
import 'ui/tone.dart';
import 'ui/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端 sqflite 没有原生实现，统一走 FFI + 随包的 sqlite3。
  if (!Platform.isAndroid) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // 预览构建：隐藏通知栏与手势条，截图里不出现系统 UI。
  // （MIUI 的 policy_control 对这个窗口不生效，只能从 App 侧 immersive。）
  if (Platform.isAndroid && const bool.fromEnvironment('DEMO_PREVIEW')) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // 第一帧立刻出开屏：开库 / 迁移 / 读设置都在开屏背后跑。
  // 旧版是在 runApp 之前 await 这些，冷启动那几百毫秒是纯白的系统窗口。
  runApp(const LightConeBootstrap());
}

/// 启动壳：开屏 → 主界面（淡入切换）。
class LightConeBootstrap extends StatefulWidget {
  const LightConeBootstrap({super.key});

  @override
  State<LightConeBootstrap> createState() => _LightConeBootstrapState();
}

class _LightConeBootstrapState extends State<LightConeBootstrap> {
  /// 设置对象先建好（还没挂仓库）：这样 MaterialApp 的树从第一帧就是稳定的，
  /// 开屏切主界面时才能做淡入，而不是整棵树重建。
  late final AppSettings _settings = AppSettings()..addListener(_onSettings);

  /// 启动自动补全要弹一条轻提示，但那时还没有页面 context。
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  AppState? _state;
  Object? _error;

  /// 首次启动（还没有任何图库）：先让用户选目录。
  bool _needsOnboarding = false;

  /// 主题对象必须缓存。
  ///
  /// `_theme` 每调用一次就返回一个新实例，而 MaterialApp 用的是
  /// AnimatedTheme（按 identity 判断要不要过渡）—— 不缓存的话，每一次
  /// setState（滚动、点收藏、状态刷新）都会重新触发一遍主题动画，
  /// 界面上就是一层层没完没了的颜色漂移。
  int? _themeSeed;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  void _ensureThemes() {
    final seed = _settings.palette.seed.toARGB32();
    if (_themeSeed == seed && _lightTheme != null) return;
    _themeSeed = seed;
    _lightTheme = _theme(Brightness.light, _settings.palette);
    _darkTheme = _theme(Brightness.dark, _settings.palette);
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    if (mounted) setState(() => _error = null);
    try {
      final db = await LightConeDb.open();
      final repo = Repository(db);
      _settings.attach(repo);
      await _settings.load();
      await repo.loadLibraryRoot();
      // 演示构建（--dart-define=DEMO_ROOT=...）：直接建演示库并塞假元数据，
      // README 截图用；正常构建里这个字符串是空的，整段不会执行。
      const demoRoot = String.fromEnvironment('DEMO_ROOT');
      // DEMO_PREVIEW：不塞假元数据、不自动补全，只扫描目录。用来拍「补全
      // 元数据」过程（库里的作品全是真实文件，元数据留给设置页手动补）。
      const demoPreview = bool.fromEnvironment('DEMO_PREVIEW');
      if (demoRoot.isNotEmpty) {
        // 每次启动都校正根目录（构建时路径被 shell 转换过也能自愈）
        await repo.setLibraryRoot(
          demoRoot,
          name: demoPreview ? 'preview' : 'demo',
        );
        if (!demoPreview) {
          await repo.seedDemoMetadata();
        }
      }
      final state = AppState(repo);
      // 有库才做迁移/清理；没有库就走首次引导（选目录）
      final hasLibrary = (await repo.libraries()).isNotEmpty;
      if (hasLibrary) {
        await repo.ensurePhoneLibrary();
      }

      // 开屏至少停 900ms：一是冷启动够快时不会一闪而过，二是要和
      // SplashScreen 里那段入场动画（900ms）对齐 —— 短了动画会被切一半。
      const minimum = Duration(milliseconds: 900);
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minimum) {
        await Future<void>.delayed(minimum - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _needsOnboarding = !hasLibrary;
      });
      // 权限请求放到主界面出来之后：系统对话框不该盖在开屏上。
      // 有库且开了自动补全时，顺便静默扫一次目录、补新作品的元数据。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_needsOnboarding) {
          await state.ensurePermission();
          return;
        }
        if (demoPreview) {
          // 预览库只扫描目录；元数据留给设置页手动补，截图才能拍到过程。
          await state.ensurePermission();
          await state.scanAll();
          return;
        }
        final notice = await state.autoSyncOnLaunch(
          enabled: _settings.autoMeta,
        );
        if (notice != null && mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(notice)),
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final error = _error;

    final Widget home;
    if (error != null) {
      home = _BootError(
        key: const ValueKey('error'),
        error: error,
        onRetry: _boot,
      );
    } else if (state == null) {
      home = const SplashScreen(key: ValueKey('splash'));
    } else if (_needsOnboarding) {
      home = OnboardingScreen(
        key: const ValueKey('onboarding'),
        state: state,
        onDone: () async {
          await state.repo.ensurePhoneLibrary();
          state.bumpData();
          if (mounted) setState(() => _needsOnboarding = false);
        },
      );
    } else {
      home = HomeShell(key: const ValueKey('home'), state: state);
    }

    _ensureThemes();
    return AppSettingsScope(
      settings: _settings,
      child: MaterialApp(
        title: '光锥图库',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        themeMode: _settings.themeMode,
        // 默认 200ms + linear 太短太硬。380ms 配 easeInOutCubic 才是
        // 「颜色慢慢化开」的观感；和下面页面切换的时长一致。
        themeAnimationDuration: const Duration(milliseconds: 380),
        themeAnimationCurve: Curves.easeInOutCubic,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: home,
        ),
      ),
    );
  }
}

/// 配色：种子色与深色底都跟着色板走（设置里可换）。
ThemeData _theme(Brightness brightness, ThemePalette palette) {
  // 有显式令牌就按令牌来（Tauri 那套工业配色）；没有才回退到种子推导。
  final raw = palette.tones?.of(brightness);
  final tones = raw == null ? null : softenTones(raw, brightness);
  final isDark = brightness == Brightness.dark;
  final scheme = tones != null
      ? colorSchemeFromTones(tones, brightness)
      : ColorScheme.fromSeed(
          seedColor: palette.seed,
          brightness: brightness,
          surface: brightness == Brightness.dark
              ? palette.darkSurface
              : const Color(0xFFF7F8FC),
        );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: tones == null
        ? null
        : <ThemeExtension<dynamic>>[ToneTokens.of(tones, brightness)],
  );

  // 令牌体系比 Material 多两级面（panel / kase、kaseHi）和三级线（hair /
  // lineFaint / lineDim），组件默认值会把这几层压平：Card 默认拿
  // surfaceContainerLow，那等于 panel —— 暗色下离 bg 只有 6 个色阶，
  // 网格上的卡片看不出边界。所以全局组件主题在这里一次性覆盖，
  // 不为「换个底色」逐屏改组件。
  final themed = tones == null
      ? base
      : base.copyWith(
          cardTheme: CardThemeData(
            color: tones.cardFace(brightness),
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            // 描边按明暗决定：浅色交给投影，深色留一条发丝线。
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ToneLayers.cardRadius),
              side: BorderSide(
                color: tones.cardLine(brightness) ?? const Color(0x00000000),
              ),
            ),
          ),
          // 分隔线一律落到 1px 发丝线：工业界面里线是结构，不是装饰。
          dividerTheme: DividerThemeData(
            color: tones.hair,
            thickness: 1,
            space: 1,
          ),
          appBarTheme: AppBarThemeData(
            backgroundColor: tones.bg,
            foregroundColor: tones.fg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: tones.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            // 浅色下 kaseHi 是近白，选中胶囊和底栏几乎同色；用强调色的
            // 淡染，选中项才有存在感。
            indicatorColor: isDark
                ? tones.kaseHi
                : tones.accent.withValues(alpha: 0.12),
          ),
          navigationRailTheme: NavigationRailThemeData(
            backgroundColor: tones.panel,
            indicatorColor: isDark
                ? tones.kaseHi
                : tones.accent.withValues(alpha: 0.12),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: tones.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: tones.hair),
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: tones.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            modalBackgroundColor: tones.panel,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          // 分段按钮的选中态在 M3 里取 secondaryContainer —— 补全配色槽位后
          // 它变成近白，选中段和底几乎同色。这里显式给一层强调色淡染。
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return isDark
                      ? tones.kaseHi
                      : tones.accent.withValues(alpha: 0.18);
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? tones.fg
                    : tones.textMuted,
              ),
              side: WidgetStatePropertyAll(BorderSide(color: tones.hair)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ToneLayers.controlRadius),
                ),
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          // 筛选芯片同理：选中态原来跟着 secondaryContainer 走。
          chipTheme: ChipThemeData(
            backgroundColor: Colors.transparent,
            selectedColor: isDark
                ? tones.kaseHi
                : tones.accent.withValues(alpha: 0.18),
            secondarySelectedColor: isDark
                ? tones.kaseHi
                : tones.accent.withValues(alpha: 0.18),
            side: BorderSide(color: tones.hair),
            labelStyle: TextStyle(color: tones.fgSoft),
            secondaryLabelStyle: TextStyle(
              color: tones.fg,
              fontWeight: FontWeight.w600,
            ),
            checkmarkColor: tones.accent,
            showCheckmark: true,
          ),
          // M3 默认按钮是全圆角胶囊，和这套直角工业排版不是一路。
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ToneLayers.controlRadius),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ToneLayers.controlRadius),
              ),
              side: BorderSide(color: tones.hair),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ToneLayers.controlRadius),
              ),
            ),
          ),
        );

  if (!Platform.isWindows) return themed;
  // Windows 默认的 Roboto/Segoe UI 对中文会落到不同的系统回退字体，
  // 同一段文字里中英混排容易粗细不一致。桌面统一用雅黑系。
  const fallback = ['Microsoft YaHei', 'Segoe UI', 'Segoe UI Emoji'];
  return themed.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: fallback,
    ),
  );
}

/// 开库失败时的兜底界面（版本不对、文件损坏等），带重试。
class _BootError extends StatelessWidget {
  const _BootError({super.key, required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              const Text('数据库打不开'),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
