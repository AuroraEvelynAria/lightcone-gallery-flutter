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

  /// 逐色插值。切深浅主题时令牌必须跟着一起过渡 —— 否则 ColorScheme 在
  /// 渐变、令牌是硬切，界面上会看到「一半丝滑一半跳帧」。
  static ToneSet lerp(ToneSet a, ToneSet b, double t) => ToneSet(
        bg: Color.lerp(a.bg, b.bg, t)!,
        fg: Color.lerp(a.fg, b.fg, t)!,
        fgSoft: Color.lerp(a.fgSoft, b.fgSoft, t)!,
        textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
        mark: Color.lerp(a.mark, b.mark, t)!,
        lineDim: Color.lerp(a.lineDim, b.lineDim, t)!,
        lineFaint: Color.lerp(a.lineFaint, b.lineFaint, t)!,
        hair: Color.lerp(a.hair, b.hair, t)!,
        panel: Color.lerp(a.panel, b.panel, t)!,
        panelHi: Color.lerp(a.panelHi, b.panelHi, t)!,
        kase: Color.lerp(a.kase, b.kase, t)!,
        kaseHi: Color.lerp(a.kaseHi, b.kaseHi, t)!,
        well: Color.lerp(a.well, b.well, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
      );
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

/// 把一个颜色的彩度按比例压低（明度、色相不动）。
Color _desaturate(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withSaturation((hsl.saturation * amount).clamp(0.0, 1.0))
      .toColor();
}

/// 柔和化：把**面积大的那几层**的彩度压下去，只留 accent 有颜色。
///
/// Tauri 的原令牌是给深底、高对比的机箱界面调的 —— 每一层都带同一档
/// 彩度。搬到浅色主题上，背景、面板、卡片、胶囊就全挤进同一个色相窄带
/// 里，层次只剩几个色阶的明度差，看上去既「糊」又「乱」：满屏都是粉的
/// 不同深浅，没有一处是中性的休止符。
///
/// 压掉大面积色的彩度之后，分层回到明度上（白卡片浮在浅灰底上），
/// 强调色重新成为整屏唯一的彩色焦点。
ToneSet softenTones(ToneSet t, Brightness brightness) {
  final amount = brightness == Brightness.dark ? 0.55 : 0.28;
  Color face(Color c) => _desaturate(c, amount);
  Color ink(Color c) => _desaturate(c, 0.55);
  return ToneSet(
    bg: face(t.bg),
    fg: ink(t.fg),
    fgSoft: ink(t.fgSoft),
    textMuted: ink(t.textMuted),
    mark: ink(t.mark),
    lineDim: face(t.lineDim),
    lineFaint: face(t.lineFaint),
    hair: face(t.hair),
    panel: face(t.panel),
    panelHi: face(t.panelHi),
    kase: face(t.kase),
    kaseHi: face(t.kaseHi),
    well: face(t.well),
    accent: t.accent,
    onAccent: t.onAccent,
  );
}

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
    // 这几个原来没给，M3 会退回一组和这套配色无关的推导色：
    // 底部导航选中图标取 onSecondaryContainer，缺它时落到 onSecondary
    // （= 背景色），浅色主题下就是「白图标压在近白胶囊上」，看不见。
    secondaryContainer: t.kaseHi,
    onSecondaryContainer: t.fg,
    tertiary: t.accent,
    onTertiary: t.onAccent,
    tertiaryContainer: t.kaseHi,
    onTertiaryContainer: t.fg,
    errorContainer: t.kase,
    onErrorContainer: t.fg,
    surfaceDim: t.well,
    surfaceBright: t.panelHi,
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

/// 明暗两套里，「浮起的面」和「看得见的边框」不是同一个令牌。
///
/// Tauri 的 `case` 表示机箱上的凹槽：浅色主题下它比 bg **暗**，当卡片底
/// 会让浅色界面发脏；深色主题下它比 bg 亮，正是要的那一层。所以卡片面按
/// 明暗取不同令牌，边框同理 —— 浅色里 hair 与面板只差十来个色阶，
/// 1px 线立不住，要落到深一级的 lineFaint。
extension ToneLayers on ToneSet {
  /// 卡片圆角 / 控件圆角。柔和版比工业版放大一档。
  static const double cardRadius = 12;
  static const double controlRadius = 8;

  /// 卡片常态面：永远取比底色亮的那一层。
  Color cardFace(Brightness brightness) =>
      brightness == Brightness.dark ? kase : panelHi;

  /// 卡片悬停面：深色提亮一档；浅色已经是最高亮面，反馈交给投影加深。
  Color cardFaceRaised(Brightness brightness) =>
      brightness == Brightness.dark ? kaseHi : panelHi;

  /// 卡片描边：深色靠一条发丝线收边；浅色不画线 —— 那里改用柔和投影
  /// 分层，线加阴影一起上会显脏。
  Color? cardLine(Brightness brightness) =>
      brightness == Brightness.dark ? hair : null;

  /// 卡片投影：浅色有、深色没有（深色靠面提亮分层，投影只会压暗）。
  ///
  /// 深色这边给的是**全透明**的投影而不是空列表：`BoxShadow.lerpList` 遇到
  /// 一边为空会走「单边缩放」分支，只缩模糊半径、alpha 不动 —— 过渡时影子
  /// 像被吸进卡片里；两边都是同构的 shadow，alpha 才能平滑淡到 0。
  List<BoxShadow> cardShadow(Brightness brightness, {bool raised = false}) {
    final alpha = brightness == Brightness.dark
        ? 0.0
        : (raised ? 0.12 : 0.07);
    return <BoxShadow>[
      // 收缩过的投影：网格间距只有十来个像素，22 以上的模糊半径会溢到
      // 相邻卡片上，看着像脏。卡片要的是「轻轻浮起」，不是浮层那种大投影。
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: alpha),
        blurRadius: raised ? 18 : 14,
        offset: Offset(0, raised ? 6 : 4),
        spreadRadius: -2,
      ),
    ];
  }
}

/// 柔和卡片的统一装饰：浅色走「白面 + 投影」，深色走「提亮面 + 发丝线」。
///
/// 放在这里而不是每处手写，是因为设置页的区块、网格里的作品卡必须长得
/// 是同一个东西 —— 两边各写一遍迟早会飘。
BoxDecoration softCardDecoration(
  BuildContext context, {
  bool raised = false,
  double radius = ToneLayers.cardRadius,
}) {
  final theme = Theme.of(context);
  final tokens = theme.extension<ToneTokens>() ??
      ToneTokens.of(
        theme.brightness == Brightness.dark
            ? kArchiveTone.dark
            : kArchiveTone.light,
        theme.brightness,
      );
  return BoxDecoration(
    color: raised ? tokens.cardRaised : tokens.card,
    borderRadius: BorderRadius.circular(radius),
    // 描边在深浅色里都要占位。BoxDecoration 的 border 是以 padding 的形式
    // 挤窄内容区的 —— 只在深色画线，切主题时整页内容就会左右各缩 1px
    // （3.25 倍屏上是 3 个物理像素，肉眼能看出「跳了一下」）。浅色用全透明
    // 的线，视觉上仍然没有描边，但布局两端一致。
    border: Border.all(color: tokens.cardLine),
    boxShadow: raised ? tokens.cardShadowRaised : tokens.cardShadow,
  );
}

/// Material 没有 hair / case / well 这几层，组件要用时从这里取。
///
/// 卡片要用的那几层（面 / 悬停面 / 描边 / 投影）在这里**提前算成颜色**，
/// 而不是留成「按 brightness 现算」的函数。原因：`ThemeData.lerp` 对
/// brightness 是离散的（过渡到中点才翻转），现算的话会在中途从 panelHi
/// 跳到 kase，颜色闪一下；定成字段之后两端都是同一个 Color，能顺着
/// `lerp` 一路渐变过去。
class ToneTokens extends ThemeExtension<ToneTokens> {
  const ToneTokens({
    required this.set,
    required this.card,
    required this.cardRaised,
    required this.cardLine,
    required this.cardShadow,
    required this.cardShadowRaised,
  });

  factory ToneTokens.of(ToneSet set, Brightness brightness) => ToneTokens(
        set: set,
        card: set.cardFace(brightness),
        cardRaised: set.cardFaceRaised(brightness),
        cardLine: set.cardLine(brightness) ?? const Color(0x00000000),
        cardShadow: set.cardShadow(brightness),
        cardShadowRaised: set.cardShadow(brightness, raised: true),
      );

  final ToneSet set;
  final Color card;
  final Color cardRaised;
  final Color cardLine;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> cardShadowRaised;

  @override
  ToneTokens copyWith({
    ToneSet? set,
    Color? card,
    Color? cardRaised,
    Color? cardLine,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? cardShadowRaised,
  }) =>
      ToneTokens(
        set: set ?? this.set,
        card: card ?? this.card,
        cardRaised: cardRaised ?? this.cardRaised,
        cardLine: cardLine ?? this.cardLine,
        cardShadow: cardShadow ?? this.cardShadow,
        cardShadowRaised: cardShadowRaised ?? this.cardShadowRaised,
      );

  @override
  ToneTokens lerp(ThemeExtension<ToneTokens>? other, double t) {
    if (other is! ToneTokens) return this;
    return ToneTokens(
      set: ToneSet.lerp(set, other.set, t),
      card: Color.lerp(card, other.card, t)!,
      cardRaised: Color.lerp(cardRaised, other.cardRaised, t)!,
      cardLine: Color.lerp(cardLine, other.cardLine, t)!,
      cardShadow:
          BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? const [],
      cardShadowRaised:
          BoxShadow.lerpList(cardShadowRaised, other.cardShadowRaised, t) ??
              const [],
    );
  }
}

/// 在组件里直接取令牌：`context.tones.hair`。
///
/// 令牌没挂进主题时（比如某个屏用了自建的 ThemeData）退回 ARCHIVE，
/// 而不是崩在 `!` 上 —— 配色缺一层只会难看，不该白屏。
extension ToneContext on BuildContext {
  ToneSet get tones {
    final theme = Theme.of(this);
    return theme.extension<ToneTokens>()?.set ??
        (theme.brightness == Brightness.dark
            ? kArchiveTone.dark
            : kArchiveTone.light);
  }
}
