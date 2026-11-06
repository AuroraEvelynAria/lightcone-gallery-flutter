import 'package:flutter/material.dart';

/// 一套配色：一个种子色 + 深色模式下的底（让「深空」感跟着色相走）。
///
/// 浅色模式统一用一块很淡的中性底，避免每个色板都要维护两套背景。
class ThemePalette {
  const ThemePalette(this.name, this.seed, this.darkSurface);

  final String name;
  final Color seed;
  final Color darkSurface;
}

const kThemePalettes = <ThemePalette>[
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
