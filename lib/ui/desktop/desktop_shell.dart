import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../artworks_screen.dart';
import '../brand.dart';
import '../browse_screen.dart';
import '../gallery_screen.dart';
import '../search_screen.dart';
import '../settings_screen.dart';

/// Windows 桌面壳：左侧栏导航 + 顶部工具栏 + 主内容区。
///
/// 手机壳（[home_shell.dart] 的 `MobileShell`）是「底部四 tab + 一条 AppBar」，
/// 那是竖屏握持的操作习惯；到 27 寸显示器上，鼠标要往下伸、键盘无处发力、
/// 内容单列居中两侧全是空。桌面壳把导航挪到左侧、操作排进顶部工具栏，并接上
/// 右键菜单与常用快捷键 —— 功能一份，骨架换一套。
///
/// 四个页面继续用 [IndexedStack] 保活：切页零成本、滚动位置与已加载数据都在。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.state});

  final AppState state;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const _sidebarWidth = 232.0;
  static const _titles = ['全部图片', '作品库', '搜索', '分类'];
  static const _tabs = [
    (icon: Icons.photo_library_outlined, active: Icons.photo_library, label: '图库'),
    (icon: Icons.folder_outlined, active: Icons.folder, label: '作品库'),
    (icon: Icons.search, active: Icons.search, label: '搜索'),
    (icon: Icons.category_outlined, active: Icons.category, label: '分类'),
  ];
  static const _searchTab = 2;

  int _index = 0;

  /// 工具栏的搜索框与搜索 tab 共用同一个控制器：两处输入永远同步，
  /// 谁改都只走一套防抖搜索逻辑（见 SearchScreen 的 `_onControllerChanged`）。
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _searchController.addListener(_onSearchText);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  /// 在工具栏搜索框里打字 = 想去搜索页：自动切到搜索 tab。
  void _onSearchText() {
    if (_searchController.text.trim().isNotEmpty && _index != _searchTab) {
      setState(() => _index = _searchTab);
    }
  }

  Future<void> _scan() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await widget.state.scanAll();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(state: widget.state),
      ),
    );
  }

  void _focusSearch() {
    setState(() => _index = _searchTab);
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _onEscape() {
    // 搜索框里有字先清掉；没有就收回焦点（避免 Esc 什么都不做显得迟钝）。
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _scan,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _buildSidebar(scheme),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(child: _buildContent(scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(ColorScheme scheme) {
    return SizedBox(
      width: _sidebarWidth,
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandHeader(),
            const SizedBox(height: 4),
            for (var i = 0; i < _tabs.length; i++)
              _NavItem(
                icon: _tabs[i].icon,
                activeIcon: _tabs[i].active,
                label: _tabs[i].label,
                selected: _index == i,
                onTap: () => setState(() => _index = i),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1, color: scheme.outlineVariant),
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: '设置',
              selected: false,
              onTap: _openSettings,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    return Column(
      children: [
        _buildToolbar(scheme),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              GalleryScreen(state: widget.state),
              ArtworksScreen(state: widget.state),
              SearchScreen(
                state: widget.state,
                controller: _searchController,
                focusNode: _searchFocus,
                // 桌面把搜索框收进顶部工具栏，页内那一条不再重复
                showInlineSearch: false,
              ),
              BrowseScreen(state: widget.state),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(ColorScheme scheme) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              _titles[_index],
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索 PID / 标题 / 画师 / 标签',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: '清空',
                          onPressed: _searchController.clear,
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (widget.state.scanning)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('扫描'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 侧栏顶部的品牌区：光锥标记 + 名字。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Row(
        children: [
          const LightConeMark(size: 30),
          const SizedBox(width: 10),
          Text(
            '光锥图库',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏的一行导航：选中态用主题色高亮，整行可点。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
