import 'package:flutter/material.dart';

import 'tone.dart';

/// 一套配色：色板标识（[seed]）+ 深色底 + 显式令牌。
///
/// [seed] 只用于**持久化与选中判断**（设置里点的是哪一块），
/// 实际颜色全部来自 [tones] —— 这九套是 Tauri 版 RhinE 体系的工业配色，
/// 15 个语义令牌靠 Material 的种子推导推不出来。
class ThemePalette {
  const ThemePalette(this.name, this.seed, this.darkSurface, {this.tones});

  final String name;
  final Color seed;
  final Color darkSurface;
  final ToneScheme? tones;
}

/// 九套配色，顺序即界面上的顺序（ARCHIVE 在最前，新装默认）。
final List<ThemePalette> kThemePalettes = <ThemePalette>[
  for (final scheme in kToneSchemes)
    ThemePalette(
      scheme.name,
      scheme.dark.accent,
      scheme.dark.bg,
      tones: scheme,
    ),
];

/// 按 seed 找色板。老设置里存的 seed 可能已经不在列表里（配色体系换过），
/// 找不到就回退到第一套，而不是崩掉或空白。
ThemePalette paletteForSeed(int seed) {
  for (final palette in kThemePalettes) {
    if (palette.seed.toARGB32() == seed) return palette;
  }
  return kThemePalettes.first;
}
