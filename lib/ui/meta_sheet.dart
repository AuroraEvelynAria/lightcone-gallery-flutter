import 'package:flutter/material.dart';

import '../pixiv/artist_avatar.dart';
import '../state/app_state.dart';

/// 元数据补全面板：待补全计数 / 代理 / 开始 / 停止 / 进度。
/// 限流参数在 PixivClient（与桌面 / Kotlin 版同一条都不放松）。
Future<void> showMetaSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _MetaSheet(state: state),
    ),
  );
}

class _MetaSheet extends StatefulWidget {
  const _MetaSheet({required this.state});

  final AppState state;

  @override
  State<_MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends State<_MetaSheet> {
  final _proxyController = TextEditingController();
  int? _pending;
  int? _pendingAvatars;
  bool _running = false;
  bool _stopRequested = false;
  int _processed = 0;
  int _total = 0;
  int _fetched = 0;
  int _failed = 0;
  bool _avatarPhase = false;
  String? _message;

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
    final proxy = await widget.state.repo.setting('pixiv_proxy') ?? '';
    final pending = await widget.state.repo.pendingMetaCount();
    final pendingAvatars = await ArtistAvatarStore.pendingCount(widget.state.repo);
    if (!mounted) return;
    setState(() {
      _proxyController.text = proxy;
      _pending = pending;
      _pendingAvatars = pendingAvatars;
    });
  }

  Future<void> _saveProxy() async {
    await widget.state.repo.setSetting('pixiv_proxy', _proxyController.text.trim());
    if (!mounted) return;
    setState(() => _message = '代理已保存');
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _stopRequested = false;
      _processed = 0;
      _total = 0;
      _fetched = 0;
      _failed = 0;
      _avatarPhase = false;
      _message = null;
    });
    // 1) 作品元数据
    final result = await widget.state.fetchMeta(
      isStopped: () => _stopRequested,
      onProgress: (processed, total) {
        if (!mounted) return;
        setState(() {
          _processed = processed;
          _total = total;
        });
      },
      onBatch: (batch) {
        if (!mounted) return;
        setState(() {
          _fetched += batch.fetched;
          _failed += batch.failed;
          if (batch.lastError != null) _message = batch.lastError;
        });
      },
    );
    if (!mounted) return;
    setState(() => _message = result);

    // 2) 画师头像：元数据之后跑，已有的直接跳过（全增量）
    if (!_stopRequested) {
      if (mounted) {
        setState(() {
          _processed = 0;
          _total = 0;
          _avatarPhase = true;
          _message = '元数据完成，开始补画师头像…';
        });
      }
      final avatars = await ArtistAvatarStore.syncAll(
        widget.state.repo,
        watchStop: () => _stopRequested,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _processed = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      final summary = StringBuffer('头像：新补 ${avatars.fetched} · '
          '跳过已有 ${avatars.skipped}');
      if (avatars.none > 0) summary.write(' · 无头像 ${avatars.none}');
      if (avatars.failed > 0) {
        summary.write(' · 失败 ${avatars.failed}');
        final reason = ArtistAvatarStore.lastError;
        if (!avatars.aborted && reason != null && reason.isNotEmpty) {
          summary.write('（最近：$reason）');
        }
      }
      if (avatars.stopped) summary.write(' · 已停止');
      if (avatars.aborted) summary.write(' · ${avatars.error}');
      setState(() => _message = '$result\n$summary');
      // 头像文件不是数据库行：分类页/作品库不会自己知道有新图，
      // 这里 bump 一次，列表按 dataVersion 重建头像。
      widget.state.bumpData();
    }

    if (!mounted) return;
    setState(() => _running = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('补全 Pixiv 元数据', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              pending == null
                  ? '统计中…'
                  : pending == 0
                      ? '全部作品都有元数据了'
                      : '还有 $pending 个 PID 待补全',
            ),
            const SizedBox(height: 2),
            Text(
              _pendingAvatars == null
                  ? '头像：统计中…'
                  : _pendingAvatars == 0
                      ? '画师头像已经都补过了'
                      : '画师头像还有 $_pendingAvatars 个没补（已有的会跳过）',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _total > 0 ? _processed / _total : null,
              ),
              const SizedBox(height: 6),
              Text(
                _avatarPhase
                    ? '画师头像 $_processed/$_total'
                    : '本批 $_processed/$_total · 成功 $_fetched · 失败 $_failed',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _proxyController,
              decoration: const InputDecoration(
                labelText: '代理（可选，与桌面端共用同一设置）',
                hintText: 'http://192.168.x.x:7897',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            // 桌面的 127.0.0.1 在手机上指向手机自己 —— 必须提醒。
            Text(
              '提示：127.0.0.1 在手机上无效（会按直连处理）；要用电脑代理请填电脑局域网 IP，'
              '并确保代理软件允许局域网连接',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(onPressed: _saveProxy, child: const Text('存代理')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _running
                      ? null
                      : (pending == null || pending == 0) &&
                              (_pendingAvatars == null || _pendingAvatars == 0)
                          ? null
                          : _start,
                  child: const Text('开始补全'),
                ),
                const SizedBox(width: 8),
                if (_running)
                  OutlinedButton(
                    onPressed: () => setState(() => _stopRequested = true),
                    child: const Text('停止'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
