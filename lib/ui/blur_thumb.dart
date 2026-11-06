import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/app_settings.dart';

/// R-18 封面打码：**只在网格层生效**，点进详情正常显示。
///
/// 设置项 `mobile_blur_r18`（默认开）。用 GPU 的 `ImageFiltered` 高斯模糊，
/// 叠一层半透明黑与 R-18 角标；缩略图本来就只有几百像素，代价可以接受。
Widget blurR18IfNeeded(BuildContext context, int xRestrict, Widget child) {
  if (xRestrict <= 0) return child;
  if (!AppSettingsScope.of(context).blurR18) return child;
  return Stack(
    fit: StackFit.expand,
    children: [
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: child,
      ),
      const ColoredBox(color: Color(0x33000000)),
      const Center(child: _R18Mark()),
    ],
  );
}

class _R18Mark extends StatelessWidget {
  const _R18Mark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'R-18',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
