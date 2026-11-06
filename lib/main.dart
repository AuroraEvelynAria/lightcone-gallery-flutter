import 'package:flutter/material.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'state/app_settings.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/palettes.dart';
import 'ui/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  AppState? _state;
  Object? _error;

  /// 首次启动（还没有任何图库）：先让用户选目录。
  bool _needsOnboarding = false;

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
      if (demoRoot.isNotEmpty) {
        // 每次启动都校正根目录（构建时路径被 shell 转换过也能自愈）
        await repo.setLibraryRoot(demoRoot, name: 'demo');
        await repo.seedDemoMetadata();
      }
      final state = AppState(repo);
      // 有库才做迁移/清理；没有库就走首次引导（选目录）
      final hasLibrary = (await repo.libraries()).isNotEmpty;
      if (hasLibrary) {
        await repo.ensurePhoneLibrary();
      }

      // 开屏至少停 600ms：否则冷启动够快时就是一闪而过的白闪
      const minimum = Duration(milliseconds: 600);
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minimum) {
        await Future<void>.delayed(minimum - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _needsOnboarding = !hasLibrary;
      });
      // 权限请求放到主界面出来之后：系统对话框不该盖在开屏上
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) state.ensurePermission();
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
      home = _BootError(key: const ValueKey('error'), error: error, onRetry: _boot);
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

    return AppSettingsScope(
      settings: _settings,
      child: MaterialApp(
        title: '光锥图库',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light, _settings.palette),
        darkTheme: _theme(Brightness.dark, _settings.palette),
        themeMode: _settings.themeMode,
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
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
    surface: brightness == Brightness.dark
        ? palette.darkSurface
        : const Color(0xFFF7F8FC),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
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
