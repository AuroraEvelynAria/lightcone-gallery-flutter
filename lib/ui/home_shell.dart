import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'artworks_screen.dart';
import 'browse_screen.dart';
import 'gallery_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// 主壳：底部四 tab + 顶栏「扫描 / 设置」。
///
/// 用 IndexedStack 而不是重建页面：切 tab 是零成本、保留滚动位置与已加载
/// 数据。四个页面启动时各拉一页，总耗时 < 100ms。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 扫描状态在 AppState 里；不监听的话顶栏的转圈不会更新
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  static const _titles = ['全部图片', '作品库', '搜索', '分类'];

  static const _tabs = [
    (
      icon: Icons.photo_library_outlined,
      active: Icons.photo_library,
      label: '图库',
    ),
    (icon: Icons.folder_outlined, active: Icons.folder, label: '作品库'),
    (icon: Icons.search, active: Icons.search, label: '搜索'),
    (icon: Icons.category_outlined, active: Icons.category, label: '分类'),
  ];

  Future<void> _scan() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await widget.state.scanAll();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 横屏/平板：底部导航换左侧 NavigationRail（pixez 的自适应布局）
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final pages = IndexedStack(
      index: _index,
      children: [
        GalleryScreen(state: widget.state),
        ArtworksScreen(state: widget.state),
        SearchScreen(state: widget.state),
        BrowseScreen(state: widget.state),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          // 扫描是高频动作（pixez 一直在加图），留一个一键入口
          if (widget.state.scanning)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '扫描图库',
              onPressed: _scan,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(state: widget.state),
                ),
              );
            },
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.active),
                        label: Text(tab.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages),
              ],
            )
          : pages,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.active),
                    label: tab.label,
                  ),
              ],
            ),
    );
  }
}
