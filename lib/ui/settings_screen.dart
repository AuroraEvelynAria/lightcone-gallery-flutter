import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../data/models.dart';
import '../media/media_channel.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'meta_sheet.dart';
import 'palettes.dart';

/// 设置页：外观（主题 / 网格密度）、数据（统计 / 扫描 / 导入 / 补全）、
/// 网络（代理）、关于。
///
/// 之前这些散在首页 ⋮ 的底部弹层里：代理占了一个输入框的位置，清空忽略这种
/// 低频动作和「扫描」并排。收进设置页之后，首页只留扫描与设置两个入口。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 与 pubspec.yaml 的 version 保持一致（没有引 package_info：为一行版本号
  // 多一个插件不划算）
  static const _version = '1.0.0+1';

  GalleryStats? _stats;
  int? _pending;
  String _dbDir = '';
  final _proxyController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.state.repo;
    final stats = await repo.stats();
    final pending = await repo.pendingMetaCount();
    final proxy = await repo.setting('pixiv_proxy') ?? '';
    final dbDir = await getDatabasesPath();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _pending = pending;
      _dbDir = dbDir;
      // 正在输入时不要覆盖用户的光标
      if (!_proxyController.selection.isValid || _proxyController.text.isEmpty) {
        _proxyController.text = proxy;
      }
    });
  }

  Future<void> _run(
    Future<String> Function() action, {
    bool rebindSettings = false,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final message = await action();
    if (!mounted) return;
    if (rebindSettings) {
      // 导入备份换掉了数据仓：设置对象要指向新库，否则写设置会撞已关闭的连接
      AppSettingsScope.of(context).attach(widget.state.repo);
    }
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String okLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _saveProxy() async {
    await widget.state.repo.setSetting(
      'pixiv_proxy',
      _proxyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('代理已保存（与桌面端共用同一设置）')),
    );
  }

  Future<void> _changeRoot() async {
    final picked = await MediaChannel.pickDirectory();
    if (picked == null || !mounted) return;
    final ok = await _confirm(
      title: '切换到「${picked.name}」？',
      content: '会在 ${picked.path} 建立/迁移图库；不在这个目录下的图片索引会被清掉'
          '（手机上的原图不会被删）。',
      okLabel: '切换',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.state.repo.setLibraryRoot(picked.path, name: picked.name);
    widget.state.bumpData();
    messenger.showSnackBar(
      const SnackBar(content: Text('目录已切换，点「扫描图库」把图收进来')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final pending = _pending;
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          _Section(
            title: '外观',
            children: [
              _ThemePicker(settings: settings),
              const Divider(height: 1),
              _PalettePicker(settings: settings),
              const Divider(height: 1),
              _ColumnPicker(settings: settings),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.blurR18,
                onChanged: (value) => settings.setBlurR18(value),
                title: const Text('模糊 R-18 封面'),
                subtitle: const Text('只在网格里打码，点进详情正常显示'),
              ),
            ],
          ),
          _Section(
            title: '数据',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: stats == null
                    ? const Text('统计中…')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatPill(label: '图片', value: stats.images),
                          _StatPill(label: '作品', value: stats.artworks),
                          _StatPill(label: '页', value: stats.pages),
                          _StatPill(label: '画师', value: stats.artists),
                          _StatPill(label: '标签', value: stats.tags),
                          _StatPill(label: '元数据', value: stats.meta),
                          _StatPill(label: '收藏', value: stats.favorites),
                        ],
                      ),
              ),
              const Divider(height: 1),
              _InfoBlock(
                icon: Icons.folder_outlined,
                title: '图库目录',
                value: widget.state.repo.libraryRoot,
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('更换图库目录'),
                subtitle: const Text('换目录会清掉不在新目录下的索引（原图不动）'),
                enabled: !_busy,
                onTap: _changeRoot,
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('扫描图库'),
                subtitle: const Text('按当前目录增量扫描'),
                enabled: !_busy,
                onTap: () => _run(widget.state.scanAll),
              ),
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: const Text('从桌面备份补元数据'),
                subtitle: const Text('只搬元数据，不换索引（免联网）'),
                enabled: !_busy,
                onTap: () => _run(widget.state.importMetadataFromBackup),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('补全 Pixiv 元数据'),
                subtitle: pending == null
                    ? const Text('统计中…')
                    : Text(pending == 0 ? '全部作品都有元数据了' : '$pending 个 PID 待补全'),
                onTap: () async {
                  await showMetaSheet(context, widget.state);
                  if (mounted) await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('导入桌面端备份'),
                subtitle: const Text('整库替换，需重新扫描'),
                enabled: !_busy,
                onTap: () async {
                  final ok = await _confirm(
                    title: '替换本机索引？',
                    content: '会把本机全部图片 / 作品索引换成备份里的内容。'
                        '桌面备份里的路径是 Windows 路径，换完之后手机上的图显示不出来，'
                        '需要再扫描一次。\n\n'
                        '收藏、评分与忽略名单也会被覆盖。',
                    okLabel: '替换',
                  );
                  if (!ok) return;
                  await _run(widget.state.importBackup, rebindSettings: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导出备份'),
                subtitle: const Text('生成 .db，桌面端「导入备份」可直接用'),
                enabled: !_busy,
                onTap: () => _run(widget.state.exportBackup),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text('清空忽略名单${stats == null ? '' : '（${stats.ignored}）'}'),
                subtitle: const Text('移出的条目会重新参与扫描'),
                enabled: !_busy && (stats?.ignored ?? 0) > 0,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await _confirm(
                    title: '清空忽略名单？',
                    content: '被移出作品库的条目会重新出现在扫描结果里。',
                    okLabel: '清空',
                  );
                  if (!ok) return;
                  await widget.state.repo.clearIgnored();
                  widget.state.bumpData();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('忽略名单已清空')),
                  );
                  await _load();
                },
              ),
            ],
          ),
          _Section(
            title: '网络',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _proxyController,
                      decoration: const InputDecoration(
                        labelText: 'Pixiv 代理（可选）',
                        hintText: 'http://192.168.x.x:7897',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '127.0.0.1 在手机上指向手机自己，会按直连处理；'
                      '要用电脑的代理请填电脑局域网 IP，并允许局域网连接。',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _saveProxy,
                        child: const Text('保存代理'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            title: '关于',
            children: [
              ListTile(
                leading: const SizedBox(
                  width: 40,
                  height: 40,
                  child: LightConeMark(size: 40, glow: false),
                ),
                title: const Text('光锥图库 · Flutter 版'),
                subtitle: Text('版本 $_version · 索引 schema v12\n'
                    '与桌面端共用同一套表结构'),
                isThreeLine: true,
              ),
              _InfoBlock(
                icon: Icons.storage_outlined,
                title: '数据库',
                value: '$_dbDir/lightcone.db',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 路径类的信息块：不用 ListTile —— 长路径会换行，ListTile 的固定行高会溢出。
class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onSelectionChanged: (value) => settings.setThemeMode(value.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('配色', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '种子色 + 对应的深色底，深浅主题都跟着换',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final palette in kThemePalettes)
                _PaletteSwatch(
                  palette: palette,
                  selected: settings.palette.seed == palette.seed,
                  onTap: () => settings.setPalette(palette),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ThemePalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.seed,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 18, color: Colors.black87)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              palette.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnPicker extends StatelessWidget {  const _ColumnPicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('网格列数', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '自动按屏宽排（约 3 列）；作品库瀑布流同此设置',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('自动')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {settings.gridColumns},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onSelectionChanged: (value) => settings.setGridColumns(value.first),
            ),
          ),
        ],
      ),
    );
  }
}
