import 'package:flutter/material.dart';

import 'brand.dart';

/// 开屏：冷启动时第一帧就出它，开库 / 迁移 / 读设置在背后跑。
///
/// 背景色与 `android/app/src/main/res/values/colors.xml` 的 splash_background
/// 一致 —— 从系统启动窗口切到 Flutter 这一帧不会闪白。
///
/// 入场是一段线性动画，不是整体缩放淡入：光点亮起 → 光锥的两条母线向下
/// 扫开 → 底部弧从两端合拢 → 填色与光晕补满 → 标题淡入、细线从中间展开。
/// 时长与 `main.dart` 里「最小开屏时间」对齐，否则冷启动够快时会被切一半。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  )..forward();

  /// 锥体占前 78%，剩下的时间留给文字，收尾才不仓促。
  late final Animation<double> _mark = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.78),
  );

  late final Animation<double> _title = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.42, 0.86, curve: Curves.easeOut),
  );

  late final Animation<double> _tagline = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.62, 1, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 开屏不在 Scaffold 里，必须自己给一个 Material：否则文字会继承
    // WidgetsApp 的「缺少 Material」错误样式（黄色双下划线）。
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1220), Color(0xFF111C33)],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _mark,
                    builder: (context, _) =>
                        LightConeMark(size: 156, progress: _mark.value),
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _title,
                    builder: (context, child) =>
                        Opacity(opacity: _title.value, child: child),
                    child: const Text(
                      '光锥图库',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 8,
                        color: Color(0xFFE8EFFF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 一条从中间向两侧展开的细线：把标题和英文落款分开，
                  // 也是整段入场里唯一的横向动作。
                  AnimatedBuilder(
                    animation: _tagline,
                    builder: (context, _) => Container(
                      width: 148 * _tagline.value,
                      height: 1,
                      color: const Color(0xFF82B1FF)
                          .withValues(alpha: 0.42 * _tagline.value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _tagline,
                    builder: (context, child) =>
                        Opacity(opacity: _tagline.value, child: child),
                    child: Text(
                      'LIGHTCONE GALLERY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3.5,
                        color: const Color(0xFF82B1FF).withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 底部一条极细的进度线：告诉用户「在准备」，而不是卡住了
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: SizedBox(
                  width: 96,
                  child: Opacity(
                    opacity: 0.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: const LinearProgressIndicator(minHeight: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
