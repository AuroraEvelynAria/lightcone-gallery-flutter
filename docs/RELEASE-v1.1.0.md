# 光锥图库 v1.1.0 · Android + Windows

第一个双端版本。Android 与 Windows 共用同一套 schema v12，元数据、收藏、评分、
标签画廊可以通过「元数据包」或整库备份互传。

## 下载

| 平台 | 文件 |
|---|---|
| Windows x64 | `lightcone-gallery-windows-x64-v1.1.0.zip` |
| Android 8.0+ | `lightcone-gallery-android-v1.1.0.apk` |

## Windows x64

- 解压后双击 `lightcone_flutter.exe`，首次启动选一个含 `{pid}_p{n}` 的图库目录。
- 独立数据库：`%APPDATA%\AuroraEvelynAria\LightCone Gallery\lightcone.db`，
  不会改动 Tauri 版的 `gallery.db`。
- 设置 → 数据 →「从 LightCone 备份补元数据」可以直接读 Tauri 的 `gallery.db`
  或手机导出的 `lightcone-*.db`；同一 PID 以较新的 `fetched_at` 为准，
  旧备份不会把已补数据降级。
- 桌面端支持两栏详情、标签画廊新建/编辑/删除、滚轮缩放、双击、`←`/`→`
  翻页与 `Esc` 关闭。
- 这是 MVP：暂不含安装包、分享、设为壁纸/锁屏与持久化缩略图缓存。

## Android

- Android 8.0+，release 包使用 debug 签名，可直接覆盖安装旧版。
- 与 Windows 端互传：设置 → 数据 →「导出 / 导入元数据包」。
- 也可把手机「导出备份」得到的 `lightcone-*.db` 拿到 Windows 端合并。

## 数据兼容

- 两端索引 schema 均为 v12；Tauri 版 v11 的 `gallery.db` 也能导入
  （缺 `match_mode` 时按 `all` 处理）。
- 元数据包只含标题/标签/画师/AI/收藏评分/标签画廊，不含原图与路径，
  约 4k 作品 1.6MB。
- 收藏/评分按 PID 取并集，评分取两边最大值；标签画廊按 id 覆盖。

## 校验

```
be74e35944812f33ca54dfd0034e9f3c7f82ca84c28ce585c3a07090c9c6ac3f  lightcone-gallery-android-v1.1.0.apk
26bc428e70d7025e618f5fa0ab1cc542249c4963a93a85004c2c5d8ba48ec9df  lightcone-gallery-windows-x64-v1.1.0.zip
```
