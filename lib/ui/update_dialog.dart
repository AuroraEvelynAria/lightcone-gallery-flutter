import 'package:flutter/material.dart';

import '../update/update_service.dart';

/// 检查更新的完整流程：检查 → 有新版 → 下载 → 拉起系统安装器。
///
/// 用对话框而不是塞进设置页：APK 几十兆，下载要几十秒，用户得看得见进度，
/// 也得能中途取消。
Future<void> showUpdateDialog(BuildContext context, {String? proxy}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(proxy: proxy),
  );
}

enum _Phase { checking, uptodate, available, downloading, done, error }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({this.proxy});

  final String? proxy;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.checking;
  UpdateInfo? _info;
  double _progress = 0;
  String _error = '';
  UpdateErrorKind _errorKind = UpdateErrorKind.other;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    // 对话框被关掉时别让下载在后台空跑。
    if (_phase == _Phase.downloading) UpdateService.cancelDownload();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _phase = _Phase.checking);
    try {
      final info = await UpdateService.check(proxy: widget.proxy, force: true);
      if (!mounted) return;
      setState(() {
        _info = info;
        _phase = info == null ? _Phase.uptodate : _Phase.available;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _errorKind = e.kind;
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final path = await UpdateService.download(
        info,
        proxy: widget.proxy,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;

      if (!await UpdateService.canInstall()) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _errorKind = UpdateErrorKind.install;
          _error = '系统还没允许「光锥图库」安装应用。去设置里打开后再点一次。';
        });
        return;
      }

      await UpdateService.install(path);
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _errorKind = e.kind;
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(width: 360, child: _body(context)),
      actions: _actions(context),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.checking:
        return '检查更新';
      case _Phase.uptodate:
        return '已是最新版';
      case _Phase.available:
        return '发现新版本';
      case _Phase.downloading:
        return '正在下载';
      case _Phase.done:
        return '下载完成';
      case _Phase.error:
        return '更新失败';
    }
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_phase) {
      case _Phase.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('正在向 GitHub 查询…'),
            ],
          ),
        );

      case _Phase.uptodate:
        return const Text('当前已是最新版本，不需要更新。');

      case _Phase.available:
        final info = _info;
        if (info == null) return const SizedBox.shrink();
        final notes = info.notes.trim();
        final sizeSuffix =
            info.sizeLabel.isEmpty ? '' : ' · ${info.sizeLabel}';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本 ${info.version}$sizeSuffix',
              style: theme.textTheme.titleSmall,
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(notes, style: theme.textTheme.bodySmall),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '下载完成后会拉起系统安装器，需要你点一下「安装」。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case _Phase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 10),
            Text(
              _progress > 0
                  ? '${(_progress * 100).round()}%'
                  : '正在连接…',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );

      case _Phase.done:
        return const Text('安装器已经打开，点「安装」即可完成更新。');

      case _Phase.error:
        return Text(_error);
    }
  }

  List<Widget> _actions(BuildContext context) {
    switch (_phase) {
      case _Phase.checking:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ];

      case _Phase.uptodate:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ];

      case _Phase.available:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: _downloadAndInstall,
            child: const Text('立即更新'),
          ),
        ];

      case _Phase.downloading:
        return [
          TextButton(
            onPressed: () {
              UpdateService.cancelDownload();
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
        ];

      case _Phase.done:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ];

      case _Phase.error:
        // 只有「缺安装权限」才给「去授权」；限流、断网这类重试才有意义。
        if (_errorKind != UpdateErrorKind.install) {
          return [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(onPressed: _check, child: const Text('重试')),
          ];
        }
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await UpdateService.openInstallSettings();
            },
            child: const Text('去授权'),
          ),
        ];
    }
  }
}
