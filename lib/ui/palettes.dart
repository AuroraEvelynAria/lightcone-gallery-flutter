import 'package:flutter/material.dart';

import 'tone.dart';

/// 一套配色：一个种子色 + 深色模式下的底（让「深空」感跟着色相走）。
///
/// 浅色模式统一用一块很淡的中性底，避免每个色板都要维护两套背景。
class ThemePalette {
  const ThemePalette(this.name, this.seed, this.darkSurface, {this.tones});

  final String name;

  /// 种子色。走 [tones] 时它只作为**色板标识**（持久化与选中判断用它），
  /// 不参与实际配色推导。
  final Color seed;
  final Color darkSurface;

  /// 显式令牌集。给了就完全按令牌来，不再让 Material 从种子色推导 ——
  /// Tauri 那套工业配色（15 个语义令牌、三级描边）靠 fromSeed 是推不出来的。
  final ToneScheme? tones;
}

const kThemePalettes = <ThemePalette>[
  // ARCHIVE 摆在第一个：新装默认就是它。数值原样来自 Tauri 版 themes.ts。
  ThemePalette('ARCHIVE', Color(0xFFFF7A01), Color(0xFF0B0B0B), tones: kArchiveTones),
  ThemePalette('深空蓝', Color(0xFF82B1FF), Color(0xFF0D1220)),
  ThemePalette('樱粉', Color(0xFFF48FB1), Color(0xFF1A1018)),
  ThemePalette('海盐青', Color(0xFF4DD0E1), Color(0xFF0A1719)),
  ThemePalette('森绿', Color(0xFF81C784), Color(0xFF0C1710)),
  ThemePalette('琥珀', Color(0xFFFFB74D), Color(0xFF1A130A)),
  ThemePalette('紫罗兰', Color(0xFFB39DDB), Color(0xFF140F1E)),
];

ThemePalette paletteForSeed(int seed) {
  for (final palette in kThemePalettes) {
    if (palette.seed.toARGB32() == seed) return palette;
  }
  return kThemePalettes.first;
}
