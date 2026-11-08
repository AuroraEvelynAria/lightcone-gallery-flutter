import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../media/directory_tree.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'directory_picker.dart';

/// 首次启动：让用户选图库目录。
///
/// 之前的版本把根写死在 `Pictures/pixez`；现在默认仍是它，但可以换成任意
/// 内部存储目录（SAF 选择的 tree URI 由原生侧解析成绝对路径）。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.state,
    required this.onDone,
  });

  final AppState state;
  final Future<void> Function() onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 先要媒体权限：没有权限的话，选完目录也扫不出东西
    widget.state.ensurePermission();
  }

  Future<void> _apply(String path, {String? name}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.repo.setLibraryRoot(path, name: name);
      await widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '创建图库失败：$e';
      });
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    final path = await showDirectoryPicker(
      context,
      initialPath: Repository.phonePictures,
    );
    if (path == null || !mounted) return;
    await _apply(path, name: DirectoryTree.nameOf(path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1220), Color(0xFF111C33)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LightConeMark(size: 120),
                  const SizedBox(height: 22),
                  const Text(
                    '光锥图库',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                      color: Color(0xFFE8EFFF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择要索引的图库目录',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF9FB4D8),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Text(
                      '只会扫描这个目录（含子目录）里的图片，其他相册不动。\n'
                      'pixez 默认下载到 Pictures/pixez；也可以换成自己的文件夹。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                                _apply(Repository.phonePictures, name: 'pixez'),
                      icon: const Icon(Icons.folder_special_outlined),
                      label: const Text('使用默认目录 Pictures/pixez'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('选择其他目录…'),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 18),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
