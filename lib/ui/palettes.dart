import 'package:flutter/material.dart';

import 'tone.dart';

/// 一套配色：色板标识（[seed]）+ 深色底 + 显式令牌。
///
/// [seed] 只用于**持久化与选中判断**（设置里点的是哪一块），
/// 实际颜色全部来自 [tones] —— 这九套是 Tauri 版 RhinE 体系的工业配色，
/// 15 个语义令牌靠 Material 的种子推导推不出来。
class ThemePalette {
  const ThemePalette(
    this.name,
    this.seed,
    this.darkSurface, {
    this.tones,
    this.label = '',
  });

  final String name;

  /// 中文名。英文名是 Tauri 版原名，留着当副标题 —— 用户认颜色不认代号。
  final String label;

  final Color seed;
  final Color darkSurface;
  final ToneScheme? tones;

  /// 界面上显示的名字：中文优先，没有中文就用英文原名。
  String get displayName => label.isEmpty ? name : label;
}

/// 九套配色的中文名。键是 Tauri 版原名（[ToneScheme.name]）。
///
/// 取名按色相气质走，统一两个字，和英文原名并排显示时不打架。
const Map<String, String> _kPaletteLabels = <String, String>{
  'ARCHIVE': '典藏',
  'HAZARD': '警戒',
  'FLARE': '耀斑',
  'FIELD': '原野',
  'COLD FRONT': '冷锋',
  'LAGOON': '潟湖',
  'IRIS': '鸢尾',
  'BLOSSOM': '绽放',
  'CRIMSON': '绯红',
};

/// 不上的两套：警戒（纯黄）和耀斑（橙红）。
///
/// 实测取色：ARCHIVE #FF7A01、HAZARD #FFCF1A、FLARE #FF6B1A —— 耀斑与典藏
/// 的 RGB 距离只有 29（九套里唯一撞的一对），警戒虽偏黄但和它们同挤在橙黄
/// 一段。留 ARCHIVE 的橙当代表，另外两套撤下；令牌定义还在 tone.dart 里，
/// 想恢复只要从这个集合里删掉名字。
const Set<String> _kRetiredPalettes = <String>{'HAZARD', 'FLARE'};

/// 配色，顺序即界面上的顺序（ARCHIVE 在最前，新装默认）。
final List<ThemePalette> kThemePalettes = <ThemePalette>[
  for (final scheme in kToneSchemes)
    if (!_kRetiredPalettes.contains(scheme.name))
      ThemePalette(
        scheme.name,
        scheme.dark.accent,
        scheme.dark.bg,
        tones: scheme,
        label: _kPaletteLabels[scheme.name] ?? '',
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
