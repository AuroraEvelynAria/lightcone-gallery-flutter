package com.lightcone.gallery.flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用更新通道。
 *
 * 只有三件事必须落在原生：读自己的版本号、查「安装未知应用」授权、
 * 拉起系统安装器。版本比对与 APK 下载都在 Dart 侧（那边有 Dio 和进度回调）。
 *
 * 和 [MediaStoreChannel] 分开：更新不是媒体职责，混在一起会让那个通道
 * 变成一个什么都装的杂物间。
 */
class UpdateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.lightcone.gallery/update"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appVersion" -> appVersion(result)
            "canInstall" -> result.success(canInstall())
            "openInstallSettings" -> openInstallSettings(result)
            "installApk" -> installApk(call, result)
            else -> result.notImplemented()
        }
    }

    /** 当前安装包的 versionName / versionCode —— Dart 侧据此判断要不要提示更新。 */
    private fun appVersion(result: MethodChannel.Result) {
        runCatching {
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            mapOf("versionName" to info.versionName, "versionCode" to code)
        }.onSuccess { result.success(it) }
            .onFailure { result.error("appVersion", it.message, null) }
    }

    /** Android 8+ 每个应用单独授权，没开时系统会直接拒绝安装，提前问比事后报错强。 */
    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    /** 跳到本应用的「安装未知应用」授权页。 */
    private fun openInstallSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }
        runCatching {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
        }.onSuccess { result.success(true) }
            .onFailure { result.error("openInstallSettings", it.message, null) }
    }

    /**
     * 拉起系统安装器。
     *
     * APK 必须落在 cache 目录：res/xml/file_paths.xml 里已经暴露了 cache-path，
     * 复用的正是分享图片用的那个 FileProvider。
     */
    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("installApk", "缺少 path", null)
            return
        }
        if (!canInstall()) {
            result.error("noPermission", "还没有允许安装未知应用", null)
            return
        }
        runCatching {
            val file = File(path)
            check(file.exists()) { "APK 不存在：$path" }
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        }.onSuccess { result.success(true) }
            .onFailure { result.error("installApk", it.message, null) }
    }
}
