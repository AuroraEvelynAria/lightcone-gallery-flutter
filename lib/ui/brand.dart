import 'package:flutter/material.dart';

/// 「光锥」标记：一个从光点向下展开的光锥。
///
/// 纯绘制、不带图片资源 —— 开屏、设置页「关于」都要用它，多一份 PNG 就多一套
/// 分辨率适配。锥体用渐变叠出来，光晕用径向渐变（不用 MaskFilter：模糊在
/// 每帧动画里太贵，开屏也要省那几毫秒）。
class LightConeMark extends StatelessWidget {
  const LightConeMark({super.key, this.size = 148, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LightConePainter(glow: glow)),
    );
  }
}

class _LightConePainter extends CustomPainter {
  const _LightConePainter({required this.glow});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final apex = Offset(size.width / 2, size.height * 0.24);
    final bottom = size.height * 0.9;
    final half = size.width * 0.31;

    // 光晕：从光点向外淡出
    if (glow) {
      final halo = Rect.fromCircle(center: apex, radius: size.width * 0.3);
      canvas.drawCircle(
        apex,
        size.width * 0.3,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFBFD6FF).withValues(alpha: 0.55),
              const Color(0xFF82B1FF).withValues(alpha: 0.18),
              const Color(0xFF82B1FF).withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(halo),
      );
    }

    // 光锥：底部用二次曲线收一点圆角，避免生硬的三角形
    final cone = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(apex.dx - half, bottom)
      ..quadraticBezierTo(apex.dx, bottom + size.height * 0.07, apex.dx + half, bottom)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.9),
            const Color(0xFF9CC0FF).withValues(alpha: 0.42),
            const Color(0xFF82B1FF).withValues(alpha: 0.06),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromLTRB(apex.dx - half, apex.dy, apex.dx + half, bottom)),
    );

    // 光锥边缘的细线，让轮廓在深色背景上立得住
    canvas.drawPath(
      cone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.006
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFDDE9FF).withValues(alpha: 0.65),
            const Color(0xFF82B1FF).withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromLTRB(apex.dx - half, apex.dy, apex.dx + half, bottom)),
    );

    // 光点
    canvas.drawCircle(
      apex,
      size.width * 0.028,
      Paint()..color = const Color(0xFFF4F8FF),
    );
    canvas.drawCircle(
      apex,
      size.width * 0.055,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.008
        ..color = const Color(0xFFDDE9FF).withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_LightConePainter oldDelegate) => oldDelegate.glow != glow;
}
