import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/palettes.dart';

/// 本机偏好：主题、网格密度。
///
/// 存进与桌面端共用的 `settings` 表，但键统一加 `mobile_` 前缀 —— 导入桌面备份
/// 会整表替换设置，这些键会丢，但读不到就等于用默认值，不影响正确性。
class AppSettings extends ChangeNotifier {
  AppSettings([this._repo]);

  Repository? _repo;

  ThemeMode _themeMode = ThemeMode.dark;
  int _gridColumns = 0; // 0 = 自动（网格按 120dp 上限算列数）
  bool _blurR18 = true; // 网格里的 R-18 封面默认打码，点进详情正常看
  ThemePalette _palette = kThemePalettes.first;

  ThemeMode get themeMode => _themeMode;

  /// 当前配色（种子色 + 深色底）。
  ThemePalette get palette => _palette;

  /// 0 = 自动；3~6 = 固定列数。
  int get gridColumns => _gridColumns;

  /// 网格里的 R-18 封面是否模糊。
  bool get blurR18 => _blurR18;

  /// 导入备份会把数据仓换成新库（旧的已关连接），设置也得跟着换，否则
  /// 之后每次改主题都会写到已关闭的 Database 上。
  void attach(Repository repo) => _repo = repo;

  Future<void> load() async {
    final repo = _repo;
    if (repo == null) return;
    final theme = await repo.setting('mobile_theme');
    final columns = int.tryParse(await repo.setting('mobile_grid_columns') ?? '');
    final blur = await repo.setting('mobile_blur_r18');
    final seed = int.tryParse(await repo.setting('mobile_theme_seed') ?? '');
    _themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark, // 默认深色：与桌面端一致，也给缩略图一个安静的底
    };
    _gridColumns = (columns == null || columns < 0 || columns > 6) ? 0 : columns;
    // 没存过 = 默认开（设置项刚加的时候主人要的就是模糊）
    _blurR18 = blur != '0';
    _palette = paletteForSeed(seed ?? kThemePalettes.first.seed.toARGB32());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _repo?.setSetting('mobile_theme', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
  }

  Future<void> setGridColumns(int columns) async {
    if (_gridColumns == columns) return;
    _gridColumns = columns;
    notifyListeners();
    await _repo?.setSetting('mobile_grid_columns', '$columns');
  }

  Future<void> setBlurR18(bool value) async {
    if (_blurR18 == value) return;
    _blurR18 = value;
    notifyListeners();
    await _repo?.setSetting('mobile_blur_r18', value ? '1' : '0');
  }

  Future<void> setPalette(ThemePalette palette) async {
    if (_palette.seed == palette.seed) return;
    _palette = palette;
    notifyListeners();
    await _repo?.setSetting('mobile_theme_seed', '${palette.seed.toARGB32()}');
  }
}

/// 把设置挂到 widget 树上：网格页读列数，设置变化时自动重建。
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope 不在树上');
    return scope!.notifier!;
  }
}
