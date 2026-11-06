import 'package:flutter/material.dart';

import 'brand.dart';

/// 开屏：冷启动时第一帧就出它，开库 / 迁移 / 读设置在背后跑。
///
/// 背景色与 `android/app/src/main/res/values/colors.xml` 的 splash_background
/// 一致 —— 从系统启动窗口切到 Flutter 这一帧不会闪白。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
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
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LightConeMark(size: 156),
                      const SizedBox(height: 30),
                      const Text(
                        '光锥图库',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 8,
                          color: Color(0xFFE8EFFF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'LIGHTCONE GALLERY',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3.5,
                          color: const Color(0xFF82B1FF).withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
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
