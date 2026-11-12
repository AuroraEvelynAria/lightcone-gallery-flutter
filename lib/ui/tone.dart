import 'package:flutter/material.dart';

/// 一套配色方案的 15 个语义令牌。
///
/// 词汇沿用 Tauri 版那套 RhinE 令牌（bg / panel / case / well / hair /
/// line-* / accent / on-accent）—— 它本来就是给「机箱陈列」这类工业界面
/// 设计的，比 Material 的 ColorScheme 细腻：描边分三级（hair 发丝线、
/// line-faint 弱分隔、line-dim 强分隔），卡片有常态与高光两面。
///
/// 不用 Material 的 surface/outline 命名，是因为两者语义对不上：
/// Material 的 surfaceContainerHighest 只有一个，这里 case 和 caseHi 是两层。
class ToneSet {
  const ToneSet({
    required this.bg,
    required this.fg,
    required this.fgSoft,
    required this.textMuted,
    required this.mark,
    required this.lineDim,
    required this.lineFaint,
    required this.hair,
    required this.panel,
    required this.panelHi,
    required this.kase,
    required this.kaseHi,
    required this.well,
    required this.accent,
    required this.onAccent,
  });

  /// 窗口/页面底色。
  final Color bg;

  /// 正文前景（最强的一档）。
  final Color fg;

  /// 次级前景。
  final Color fgSoft;

  /// 弱化文本：说明、计数。
  final Color textMuted;

  /// 最弱的标记色：分隔符、序号。
  final Color mark;

  /// 强分隔线。
  final Color lineDim;

  /// 弱分隔线。
  final Color lineFaint;

  /// 1px 发丝线。
  final Color hair;

  /// 面板底。
  final Color panel;

  /// 面板高光面。
  final Color panelHi;

  /// 卡片底（网格里的格子）。case 是关键字，所以叫 kase。
  final Color kase;

  /// 卡片高光面。
  final Color kaseHi;

  /// 内凹区域：输入框、凹槽。
  final Color well;

  /// 强调色。
  final Color accent;

  /// 强调色上的文字。
  final Color onAccent;
}

/// 一个配色方案：明暗两套令牌。
class ToneScheme {
  const ToneScheme({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final ToneSet light;
  final ToneSet dark;

  ToneSet of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// ARCHIVE：近黑 / 暖纸白 + 橙色强调。
///
/// 数值原样取自 Tauri 版 src/lib/themes.ts 的 archive，一个都没改 ——
/// 先搬一套看观感，对了再搬其余八套。
const kArchiveTones = ToneScheme(
  name: 'ARCHIVE',
  light: ToneSet(
    bg: Color(0xFFEEEDE7),
    fg: Color(0xFF252821),
    fgSoft: Color(0xFF4D4F49),
    textMuted: Color(0xFF63665D),
    mark: Color(0xFF8D9185),
    lineDim: Color(0xFF8A8A84),
    lineFaint: Color(0xFFCACAC3),
    hair: Color(0xFFD2D1CB),
    panel: Color(0xFFF4F3EE),
    panelHi: Color(0xFFFAF9F4),
    kase: Color(0xFFE4E2DA),
    kaseHi: Color(0xFFFBFAF5),
    well: Color(0xFFE3E2DB),
    accent: Color(0xFFFF7A01),
    onAccent: Color(0xFF0B0B0B),
  ),
  dark: ToneSet(
    bg: Color(0xFF0B0B0B),
    fg: Color(0xFFF2F0EA),
    fgSoft: Color(0xFFBBB9B4),
    textMuted: Color(0xFF8C8B88),
    mark: Color(0xFF8A8984),
    lineDim: Color(0xFF73726F),
    lineFaint: Color(0xFF393938),
    hair: Color(0xFF30302F),
    panel: Color(0xFF111110),
    panelHi: Color(0xFF181817),
    kase: Color(0xFF1B1B1A),
    kaseHi: Color(0xFF2B2B29),
    well: Color(0xFF121212),
    accent: Color(0xFFFF7A01),
    onAccent: Color(0xFF0B0B0B),
  ),
);

/// 把令牌映射成 Material 的 ColorScheme，让现有组件不改一行就吃到新配色。
///
/// 映射是个取舍：Material 的层级比这套令牌少，case 与 caseHi 只能各挑一个
/// 位置安放；outlineVariant 收线-faint、outline 收线-dim。
ColorScheme colorSchemeFromTones(ToneSet t, Brightness brightness) {
  return ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.kaseHi,
    onPrimaryContainer: t.fg,
    secondary: t.fgSoft,
    onSecondary: t.bg,
    error: const Color(0xFFD24B3E),
    onError: const Color(0xFFFFFFFF),
    surface: t.bg,
    onSurface: t.fg,
    surfaceContainerLowest: t.well,
    surfaceContainerLow: t.panel,
    surfaceContainer: t.panel,
    surfaceContainerHigh: t.kaseHi,
    surfaceContainerHighest: t.kase,
    onSurfaceVariant: t.textMuted,
    outline: t.lineDim,
    outlineVariant: t.lineFaint,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: t.fg,
    onInverseSurface: t.bg,
    inversePrimary: t.accent,
  );
}

/// Material 没有 hair / case / well 这几层，组件要用时从这里取。
class ToneTokens extends ThemeExtension<ToneTokens> {
  const ToneTokens(this.set);

  final ToneSet set;

  @override
  ToneTokens copyWith({ToneSet? set}) => ToneTokens(set ?? this.set);

  @override
  ToneTokens lerp(ThemeExtension<ToneTokens>? other, double t) => this;
}
