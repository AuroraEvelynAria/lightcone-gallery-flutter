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

/// 九套配色，全部原样取自 Tauri 版 src/lib/themes.ts（RhinE 体系），
/// 色值一个没改。每套明暗两版、15 个语义令牌。
///
/// 顺序即配色选择器里的顺序，ARCHIVE 在最前（新装默认）。
const kArchiveTone = ToneScheme(
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

const kHazardTone = ToneScheme(
  name: 'HAZARD',
  light: ToneSet(
    bg: Color(0xFFEBE8DC),
    fg: Color(0xFF1A1A16),
    fgSoft: Color(0xFF45443C),
    textMuted: Color(0xFF5F5D53),
    mark: Color(0xFF86857D),
    lineDim: Color(0xFF8A877C),
    lineFaint: Color(0xFFC5C3B8),
    hair: Color(0xFFCECBC0),
    panel: Color(0xFFF2EFE2),
    panelHi: Color(0xFFF8F5E8),
    kase: Color(0xFFDFDCD1),
    kaseHi: Color(0xFFF9F6E9),
    well: Color(0xFFDFDCD1),
    accent: Color(0xFFF2B800),
    onAccent: Color(0xFF1A1A16),
  ),
  dark: ToneSet(
    bg: Color(0xFF0D0D0B),
    fg: Color(0xFFF2EFE4),
    fgSoft: Color(0xFFBCB8AB),
    textMuted: Color(0xFF8F8B7F),
    mark: Color(0xFF8A8982),
    lineDim: Color(0xFF6F6C62),
    lineFaint: Color(0xFF3B3A37),
    hair: Color(0xFF32312E),
    panel: Color(0xFF131310),
    panelHi: Color(0xFF1A1A17),
    kase: Color(0xFF1D1D1A),
    kaseHi: Color(0xFF2D2C29),
    well: Color(0xFF141412),
    accent: Color(0xFFFFCF1A),
    onAccent: Color(0xFF0D0D0B),
  ),
);

const kFlareTone = ToneScheme(
  name: 'FLARE',
  light: ToneSet(
    bg: Color(0xFFF5ECE2),
    fg: Color(0xFF26170C),
    fgSoft: Color(0xFF503A28),
    textMuted: Color(0xFF6A594A),
    mark: Color(0xFF97897B),
    lineDim: Color(0xFF94887A),
    lineFaint: Color(0xFFD3C6B7),
    hair: Color(0xFFDDD1C2),
    panel: Color(0xFFFBF3E9),
    panelHi: Color(0xFFFFF9F0),
    kase: Color(0xFFECDFD0),
    kaseHi: Color(0xFFFFF8EC),
    well: Color(0xFFECDFD0),
    accent: Color(0xFFFF6B1A),
    onAccent: Color(0xFF1C0D02),
  ),
  dark: ToneSet(
    bg: Color(0xFF140A05),
    fg: Color(0xFFFFE9DA),
    fgSoft: Color(0xFFFFB991),
    textMuted: Color(0xFFD98A5C),
    mark: Color(0xFF95847A),
    lineDim: Color(0xFF9A5A35),
    lineFaint: Color(0xFF433730),
    hair: Color(0xFF3A2E27),
    panel: Color(0xFF1A100A),
    panelHi: Color(0xFF211611),
    kase: Color(0xFF241914),
    kaseHi: Color(0xFF342922),
    well: Color(0xFF1B110C),
    accent: Color(0xFFFF6B1A),
    onAccent: Color(0xFF140A05),
  ),
);

const kFieldTone = ToneScheme(
  name: 'FIELD',
  light: ToneSet(
    bg: Color(0xFFEDF1E6),
    fg: Color(0xFF1C261A),
    fgSoft: Color(0xFF435040),
    textMuted: Color(0xFF59665A),
    mark: Color(0xFF888F84),
    lineDim: Color(0xFF859183),
    lineFaint: Color(0xFFC7CDC1),
    hair: Color(0xFFD0D4C9),
    panel: Color(0xFFF4F7ED),
    panelHi: Color(0xFFFAFEF3),
    kase: Color(0xFFE1E5DA),
    kaseHi: Color(0xFFFBFFF4),
    well: Color(0xFFE1E5DA),
    accent: Color(0xFF1FA84F),
    onAccent: Color(0xFF1C261A),
  ),
  dark: ToneSet(
    bg: Color(0xFF090D09),
    fg: Color(0xFFE7F1E3),
    fgSoft: Color(0xFFB2C0AD),
    textMuted: Color(0xFF869683),
    mark: Color(0xFF838A80),
    lineDim: Color(0xFF66755F),
    lineFaint: Color(0xFF363B35),
    hair: Color(0xFF2D322C),
    panel: Color(0xFF0F130E),
    panelHi: Color(0xFF151A15),
    kase: Color(0xFF181D18),
    kaseHi: Color(0xFF282C27),
    well: Color(0xFF101410),
    accent: Color(0xFF4FDC76),
    onAccent: Color(0xFF090D09),
  ),
);

const kColdFrontTone = ToneScheme(
  name: 'COLD FRONT',
  light: ToneSet(
    bg: Color(0xFFE9EEF3),
    fg: Color(0xFF15202B),
    fgSoft: Color(0xFF3E4A57),
    textMuted: Color(0xFF56636F),
    mark: Color(0xFF838B93),
    lineDim: Color(0xFF84909B),
    lineFaint: Color(0xFFC3C9CF),
    hair: Color(0xFFCBD1D7),
    panel: Color(0xFFF0F5F9),
    panelHi: Color(0xFFF6FBFF),
    kase: Color(0xFFDDE2E8),
    kaseHi: Color(0xFFF7FCFF),
    well: Color(0xFFDDE2E8),
    accent: Color(0xFF1F6FFF),
    onAccent: Color(0xFFE9EEF3),
  ),
  dark: ToneSet(
    bg: Color(0xFF070A0F),
    fg: Color(0xFFE5EDF6),
    fgSoft: Color(0xFFAEBCCB),
    textMuted: Color(0xFF83919F),
    mark: Color(0xFF81868D),
    lineDim: Color(0xFF5F6D7B),
    lineFaint: Color(0xFF34383D),
    hair: Color(0xFF2B2F34),
    panel: Color(0xFF0D1015),
    panelHi: Color(0xFF13171C),
    kase: Color(0xFF161A1F),
    kaseHi: Color(0xFF26292F),
    well: Color(0xFF0E1116),
    accent: Color(0xFF3D8BFF),
    onAccent: Color(0xFF070A0F),
  ),
);

const kLagoonTone = ToneScheme(
  name: 'LAGOON',
  light: ToneSet(
    bg: Color(0xFFE6EFED),
    fg: Color(0xFF0F2523),
    fgSoft: Color(0xFF374F4C),
    textMuted: Color(0xFF4F6663),
    mark: Color(0xFF7E918E),
    lineDim: Color(0xFF7D8F8C),
    lineFaint: Color(0xFFC0CFCC),
    hair: Color(0xFFCBD8D5),
    panel: Color(0xFFEDF5F3),
    panelHi: Color(0xFFF2FBF9),
    kase: Color(0xFFD9E5E2),
    kaseHi: Color(0xFFEFFAF8),
    well: Color(0xFFD9E5E2),
    accent: Color(0xFF0E9188),
    onAccent: Color(0xFFEAF6F4),
  ),
  dark: ToneSet(
    bg: Color(0xFF060C0B),
    fg: Color(0xFFE0EFEC),
    fgSoft: Color(0xFFA3BCB8),
    textMuted: Color(0xFF7B918D),
    mark: Color(0xFF7D8683),
    lineDim: Color(0xFF5A6E6A),
    lineFaint: Color(0xFF313B39),
    hair: Color(0xFF2A3331),
    panel: Color(0xFF0A1211),
    panelHi: Color(0xFF101A18),
    kase: Color(0xFF121D1B),
    kaseHi: Color(0xFF22302D),
    well: Color(0xFF0B1312),
    accent: Color(0xFF2ED3C3),
    onAccent: Color(0xFF06110F),
  ),
);

const kIrisTone = ToneScheme(
  name: 'IRIS',
  light: ToneSet(
    bg: Color(0xFFECE9F3),
    fg: Color(0xFF1D1730),
    fgSoft: Color(0xFF443C5E),
    textMuted: Color(0xFF5C5474),
    mark: Color(0xFF8A84A0),
    lineDim: Color(0xFF867F9C),
    lineFaint: Color(0xFFCBC5DA),
    hair: Color(0xFFD3CEE0),
    panel: Color(0xFFF3F0F9),
    panelHi: Color(0xFFF9F6FE),
    kase: Color(0xFFE1DCEA),
    kaseHi: Color(0xFFF8F4FF),
    well: Color(0xFFE1DCEA),
    accent: Color(0xFF7C3AED),
    onAccent: Color(0xFFF3F0F9),
  ),
  dark: ToneSet(
    bg: Color(0xFF0A0813),
    fg: Color(0xFFEAE6F6),
    fgSoft: Color(0xFFB5AECB),
    textMuted: Color(0xFF8A83A1),
    mark: Color(0xFF858190),
    lineDim: Color(0xFF645D7E),
    lineFaint: Color(0xFF363249),
    hair: Color(0xFF2F2B40),
    panel: Color(0xFF0F0D1A),
    panelHi: Color(0xFF161327),
    kase: Color(0xFF151225),
    kaseHi: Color(0xFF272242),
    well: Color(0xFF0D0B16),
    accent: Color(0xFFA78BFA),
    onAccent: Color(0xFF0A0813),
  ),
);

const kBlossomTone = ToneScheme(
  name: 'BLOSSOM',
  light: ToneSet(
    bg: Color(0xFFF4EAEE),
    fg: Color(0xFF2C151F),
    fgSoft: Color(0xFF563A47),
    textMuted: Color(0xFF6F545F),
    mark: Color(0xFF9D8791),
    lineDim: Color(0xFF99818C),
    lineFaint: Color(0xFFD9C7CF),
    hair: Color(0xFFE1D1D8),
    panel: Color(0xFFFAF0F4),
    panelHi: Color(0xFFFFF5F9),
    kase: Color(0xFFECDBE2),
    kaseHi: Color(0xFFFFF3F8),
    well: Color(0xFFECDBE2),
    accent: Color(0xFFD6336C),
    onAccent: Color(0xFFFDF2F6),
  ),
  dark: ToneSet(
    bg: Color(0xFF120A0E),
    fg: Color(0xFFF5E7ED),
    fgSoft: Color(0xFFC5A9B5),
    textMuted: Color(0xFF947F8A),
    mark: Color(0xFF8D8087),
    lineDim: Color(0xFF745E69),
    lineFaint: Color(0xFF3E3239),
    hair: Color(0xFF362B31),
    panel: Color(0xFF180F13),
    panelHi: Color(0xFF201519),
    kase: Color(0xFF1F1218),
    kaseHi: Color(0xFF312329),
    well: Color(0xFF140C10),
    accent: Color(0xFFF0679E),
    onAccent: Color(0xFF120A0E),
  ),
);

const kCrimsonTone = ToneScheme(
  name: 'CRIMSON',
  light: ToneSet(
    bg: Color(0xFFF2EAEA),
    fg: Color(0xFF2B1416),
    fgSoft: Color(0xFF583A3C),
    textMuted: Color(0xFF715759),
    mark: Color(0xFF9D888A),
    lineDim: Color(0xFF988284),
    lineFaint: Color(0xFFDCCACB),
    hair: Color(0xFFE3D2D3),
    panel: Color(0xFFF9F0F0),
    panelHi: Color(0xFFFFF5F5),
    kase: Color(0xFFEADBDC),
    kaseHi: Color(0xFFFFF3F4),
    well: Color(0xFFEADBDC),
    accent: Color(0xFFD22638),
    onAccent: Color(0xFFFDF2F3),
  ),
  dark: ToneSet(
    bg: Color(0xFF100809),
    fg: Color(0xFFF5E6E7),
    fgSoft: Color(0xFFC7A9AB),
    textMuted: Color(0xFF968082),
    mark: Color(0xFF8E8183),
    lineDim: Color(0xFF776062),
    lineFaint: Color(0xFF403234),
    hair: Color(0xFF382C2E),
    panel: Color(0xFF170D0E),
    panelHi: Color(0xFF1F1314),
    kase: Color(0xFF1E1213),
    kaseHi: Color(0xFF2F2223),
    well: Color(0xFF120A0B),
    accent: Color(0xFFEF4655),
    onAccent: Color(0xFF100809),
  ),
);

/// 全部配色方案，顺序即界面上的顺序。
const List<ToneScheme> kToneSchemes = <ToneScheme>[
  kArchiveTone,
  kHazardTone,
  kFlareTone,
  kFieldTone,
  kColdFrontTone,
  kLagoonTone,
  kIrisTone,
  kBlossomTone,
  kCrimsonTone,
];

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
