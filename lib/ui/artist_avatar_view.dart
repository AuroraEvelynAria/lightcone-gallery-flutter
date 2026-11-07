import 'dart:io';

import 'package:flutter/material.dart';

import '../pixiv/artist_avatar.dart';
import '../state/app_state.dart';

/// 画师头像：有本地缓存就显示，没有先显示首字母。
///
/// [fetch] = true（详情页 / 画师页头部）时会在后台按需拉一次；
/// 列表里（分类页）用 false —— 一屏几十行，逐行联网会把 Pixiv 打爆，
/// 只显示「补全元数据」批量补好的缓存。
class ArtistAvatarView extends StatefulWidget {
  const ArtistAvatarView({
    super.key,
    required this.state,
    required this.uid,
    required this.name,
    this.radius = 18,
    this.fetch = true,
  });

  final AppState state;
  final String? uid;
  final String name;
  final double radius;
  final bool fetch;

  @override
  State<ArtistAvatarView> createState() => _ArtistAvatarViewState();
}

class _ArtistAvatarViewState extends State<ArtistAvatarView> {
  File? _file;
  DateTime? _stamp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArtistAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      setState(() {
        _file = null;
        _stamp = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final uid = widget.uid;
    if (uid == null || uid.isEmpty) return;
    final cached = await ArtistAvatarStore.cached(uid);
    if (cached != null) await _show(cached);
    if (!widget.fetch) return;
    final file = await ArtistAvatarStore.ensure(widget.state.repo, uid);
    if (file != null) await _show(file);
  }

  Future<void> _show(File file) async {
    final DateTime stamp;
    try {
      stamp = (await file.stat()).modified;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (_file?.path == file.path && _stamp == stamp) return;
    // 同一路径刷新后 FileImage 会命中旧缓存，先 evict 再换
    await FileImage(file).evict();
    if (!mounted) return;
    setState(() {
      _file = file;
      _stamp = stamp;
    });
  }

  Widget _fallback(ColorScheme scheme) {
    final name = widget.name.trim();
    final initial = name.isEmpty ? '?' : name.characters.first;
    return Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: widget.radius * 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.radius * 2;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: _file == null
            ? _fallback(scheme)
            : Image.file(
                _file!,
                key: ValueKey(
                  '${_file!.path}-${_stamp?.millisecondsSinceEpoch}',
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(scheme),
              ),
      ),
    );
  }
}
