import 'package:flutter/material.dart';

/// 「光锥」标记：一个从光点向下展开的光锥。
///
/// 纯绘制、不带图片资源 —— 开屏、设置页「关于」都要用它，多一份 PNG 就多一套
/// 分辨率适配。锥体用渐变叠出来，光晕用径向渐变（不用 MaskFilter：模糊在
/// 每帧动画里太贵，开屏也要省那几毫秒）。
class LightConeMark extends StatelessWidget {
  const LightConeMark({
    super.key,
    this.size = 148,
    this.glow = true,
    this.progress = 1,
  });

  final double size;
  final bool glow;

  /// 0 = 只剩一个光点，1 = 完整光锥。
  ///
  /// 开屏把它从 0 推到 1，锥体就是「画」出来的：母线先向下扫开，底部弧
  /// 再从两端合拢，最后填色与光晕补满。静态调用点保持默认 1。
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LightConePainter(glow: glow, progress: progress),
      ),
    );
  }
}

class _LightConePainter extends CustomPainter {
  const _LightConePainter({required this.glow, required this.progress});

  final bool glow;
  final double progress;

  /// 生长分段：母线走完 / 底部弧闭合。之后是把面与光晕补满。
  static const double _edgeDone = 0.58;
  static const double _arcDone = 0.86;

  static const Color _haloCore = Color(0xFFBFD6FF);
  static const Color _haloMid = Color(0xFF82B1FF);
  static const Color _edgeTop = Color(0xFFDDE9FF);

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;

    final apex = Offset(size.width / 2, size.height * 0.24);
    final bottom = size.height * 0.9;
    final half = size.width * 0.31;
    final bounds = Rect.fromLTRB(apex.dx - half, apex.dy, apex.dx + half, bottom);

    // 母线：从光点向下扫到底
    final edgeT = Curves.easeOutCubic.transform((p / _edgeDone).clamp(0.0, 1.0));
    // 底部弧：左右两段同时往中间合拢
    final arcT = Curves.easeInOut.transform(
      ((p - _edgeDone * 0.55) / (_arcDone - _edgeDone * 0.55)).clamp(0.0, 1.0),
    );
    // 面与光晕：最后补满，锥体才有体积
    final fillT = ((p - 0.42) / 0.58).clamp(0.0, 1.0);

    // 光晕：从光点向外淡出
    if (glow && fillT > 0) {
      final halo = Rect.fromCircle(center: apex, radius: size.width * 0.3);
      canvas.drawCircle(
        apex,
        size.width * 0.3,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _haloCore.withValues(alpha: 0.55 * fillT),
              _haloMid.withValues(alpha: 0.18 * fillT),
              _haloMid.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(halo),
      );
    }

    // 光锥面：底部用二次曲线收一点圆角，避免生硬的三角形
    if (fillT > 0) {
      final cone = Path()
        ..moveTo(apex.dx, apex.dy)
        ..lineTo(apex.dx - half, bottom)
        ..quadraticBezierTo(
          apex.dx,
          bottom + size.height * 0.07,
          apex.dx + half,
          bottom,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: 0.9 * fillT),
              const Color(0xFF9CC0FF).withValues(alpha: 0.42 * fillT),
              _haloMid.withValues(alpha: 0.06 * fillT),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(bounds),
      );
    }

    // 边缘的细线，让轮廓在深色背景上立得住；也是「画出来」的那一笔
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.006
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _edgeTop.withValues(alpha: 0.65),
          _haloMid.withValues(alpha: 0.05),
        ],
      ).createShader(bounds);

    if (edgeT > 0) {
      final reach = (bottom - apex.dy) * edgeT;
      canvas.drawLine(apex, Offset(apex.dx - half, apex.dy + reach), stroke);
      canvas.drawLine(apex, Offset(apex.dx + half, apex.dy + reach), stroke);
    }
    if (arcT > 0) {
      final arc = Path()
        ..moveTo(apex.dx - half, bottom)
        ..quadraticBezierTo(
          apex.dx,
          bottom + size.height * 0.07,
          apex.dx + half,
          bottom,
        );
      for (final metric in arc.computeMetrics()) {
        final reach = metric.length * arcT / 2;
        canvas.drawPath(metric.extractPath(0, reach), stroke);
        canvas.drawPath(
          metric.extractPath(metric.length - reach, metric.length),
          stroke,
        );
      }
    }

    // 光点：先出现，锥体从它身上长出来
    final dotT = Curves.easeOut.transform((p / 0.22).clamp(0.0, 1.0));
    if (dotT > 0) {
      canvas.drawCircle(
        apex,
        size.width * 0.028 * dotT,
        Paint()..color = const Color(0xFFF4F8FF),
      );
      canvas.drawCircle(
        apex,
        size.width * 0.055 * dotT,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.008
          ..color = _edgeTop.withValues(alpha: 0.7 * dotT),
      );
    }
  }

  @override
  bool shouldRepaint(_LightConePainter oldDelegate) =>
      oldDelegate.glow != glow || oldDelegate.progress != progress;
}
