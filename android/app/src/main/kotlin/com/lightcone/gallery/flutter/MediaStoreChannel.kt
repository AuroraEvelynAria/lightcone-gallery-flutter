package com.lightcone.gallery.flutter

import android.Manifest
import android.app.Activity
import android.app.WallpaperManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * MediaStore 通道：Flutter 侧只拿到「要什么」，枚举与缩略图全在原生侧做。
 *
 * 为什么不用插件：相册网格的流畅度取决于**物料**——系统缩略图（MediaProvider
 * 预生成、系统级缓存）与一次 MediaStore 枚举（25k 行 ~ 1 秒）。这两件事在
 * Android 原生侧各是一个 API 调用，自己写通道比引入插件更可控。
 */
class MediaStoreChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.lightcone.gallery/media"
        private const val REQUEST_MEDIA = 41
        private const val REQUEST_PICK = 42
        private const val REQUEST_PICK_DIR = 43
        private const val REQUEST_CREATE = 44
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    /** 缩略图请求可能很密：固定 2 线程，别把主线程拖下水 */
    private val io = Executors.newFixedThreadPool(2)
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingPickDir: MethodChannel.Result? = null
    private var pendingCreate: MethodChannel.Result? = null
    private var pendingCreateSource: String? = null

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_MEDIA) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "listImages" -> io.execute {
                val rows = runCatching { listImages() }
                main.post {
                    rows.onSuccess(result::success).onFailure { result.error("list", it.message, null) }
                }
            }
            "thumbnail" -> {
                val id = (call.argument<Number>("id"))?.toLong()
                val size = (call.argument<Number>("size"))?.toInt() ?: 400
                if (id == null) {
                    result.error("thumbnail", "缺少 id", null)
                } else {
                    io.execute {
                        val bytes = runCatching { thumbnailBytes(id, size) }.getOrNull()
                        main.post { result.success(bytes) }
                    }
                }
            }
            "pickBackup" -> pickBackup(result)
            "pickDirectory" -> pickDirectory(result)
            "exportBackup" -> exportBackup(call, result)
            "openUrl" -> openUrl(call, result)
            "shareImages" -> shareImages(call, result)
            "saveToGallery" -> saveToGallery(call, result)
            "setWallpaper" -> setWallpaper(call, result)
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean = requiredPermissions().all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("permission", "已有请求在进行", null)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(activity, requiredPermissions(), REQUEST_MEDIA)
    }

    /** 选图库目录：SAF 的 tree URI 转成 MediaStore 用的绝对路径前缀。 */
    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPickDir != null) {
            result.error("pickDirectory", "已有选择在进行", null)
            return
        }
        pendingPickDir = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_PICK_DIR)
    }

    private fun resolveTreePath(uri: android.net.Uri): Map<String, Any>? {
        val docId = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull() ?: return null
        val parts = docId.split(':', limit = 2)
        if (parts.isEmpty()) return null
        val volume = parts[0]
        val relative = parts.getOrElse(1) { "" }.trim('/')
        val path = if (volume == "primary") {
            "/storage/emulated/0" + if (relative.isEmpty()) "" else "/$relative"
        } else {
            "/storage/$volume" + if (relative.isEmpty()) "" else "/$relative"
        }
        val name = relative.substringAfterLast('/').ifEmpty { volume }
        return mapOf("path" to path, "name" to name)
    }

    /** 导出备份：让用户选保存位置，再把源文件拷过去。 */
    private fun exportBackup(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val name = call.argument<String>("name") ?: "lightcone-backup.db"
        if (source == null || !File(source).exists()) {
            result.error("exportBackup", "源文件不存在", null)
            return
        }
        if (pendingCreate != null) {
            result.error("exportBackup", "已有导出在进行", null)
            return
        }
        pendingCreate = result
        pendingCreateSource = source
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        activity.startActivityForResult(intent, REQUEST_CREATE)
    }

    /** 选桌面备份：SAF 打开 + 拷进 cache（导入器只认本地路径）。 */
    private fun pickBackup(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("pick", "已有选择在进行", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        activity.startActivityForResult(intent, REQUEST_PICK)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CREATE) {
            val result = pendingCreate ?: return
            val source = pendingCreateSource
            pendingCreate = null
            pendingCreateSource = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || source == null) {
                result.success(null)
                return
            }
            io.execute {
                val ok = runCatching {
                    activity.contentResolver.openOutputStream(uri)?.use { out ->
                        File(source).inputStream().use { input -> input.copyTo(out) }
                    } ?: error("无法写入目标文件")
                }.isSuccess
                main.post {
                    if (ok) {
                        result.success(uri.toString())
                    } else {
                        result.error("exportBackup", "写入失败", null)
                    }
                }
            }
            return
        }
        if (requestCode == REQUEST_PICK_DIR) {
            val result = pendingPickDir ?: return
            pendingPickDir = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            val dir = resolveTreePath(uri)
            if (dir == null) {
                result.error("pickDirectory", "无法解析目录路径", null)
            } else {
                result.success(dir)
            }
            return
        }
        if (requestCode != REQUEST_PICK) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        io.execute {
            val path = runCatching {
                val temp = File(activity.cacheDir, "import-${System.currentTimeMillis()}.db")
                activity.contentResolver.openInputStream(uri)?.use { input ->
                    temp.outputStream().use { output -> input.copyTo(output) }
                }
                temp.absolutePath
            }.getOrNull()
            main.post { result.success(path) }
        }
    }

    /** 系统分享：一张走 ACTION_SEND，多张走 ACTION_SEND_MULTIPLE。 */
    private fun shareImages(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        val text = call.argument<String>("text")
        // 以「文件」分享：接收方（微信/QQ）按文件处理，不会再压成聊天图
        val asFile = call.argument<Boolean>("asFile") ?: false
        if (paths.isEmpty()) {
            result.error("share", "没有要分享的文件", null)
            return
        }
        val uris = ArrayList<Uri>()
        for (path in paths) {
            val file = File(path)
            if (!file.exists()) continue
            uris.add(
                FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.fileprovider",
                    file,
                ),
            )
        }
        if (uris.isEmpty()) {
            result.error("share", "文件不存在", null)
            return
        }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE)
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = if (asFile) "application/octet-stream" else mimeOf(paths.first())
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (!text.isNullOrBlank()) intent.putExtra(Intent.EXTRA_TEXT, text)
        activity.startActivity(Intent.createChooser(intent, "分享图片"))
        result.success(true)
    }

    /** 保存原图到相册（Pictures/LightCone），发送时勾「原图」即可不压缩。 */
    private fun saveToGallery(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null || !File(path).exists()) {
            result.error("saveToGallery", "文件不存在", null)
            return
        }
        val name = call.argument<String>("name") ?: File(path).name
        io.execute {
            val outcome = runCatching {
                val resolver = activity.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, mimeOf(path))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(
                            MediaStore.Images.Media.RELATIVE_PATH,
                            "Pictures/LightCone",
                        )
                    }
                }
                val uri = resolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: error("无法创建相册条目")
                resolver.openOutputStream(uri)?.use { out ->
                    File(path).inputStream().use { input -> input.copyTo(out) }
                } ?: error("无法写入相册")
            }
            main.post {
                outcome.onSuccess { result.success(true) }
                    .onFailure { result.error("saveToGallery", it.message ?: "保存失败", null) }
            }
        }
    }

    /** 设为壁纸：target = home / lock / both。解码按屏幕宽降采样，避免大图 OOM。 */
    private fun setWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val target = call.argument<String>("target") ?: "home"
        if (path == null || !File(path).exists()) {
            result.error("setWallpaper", "文件不存在", null)
            return
        }
        io.execute {
            val outcome = runCatching {
                val manager = WallpaperManager.getInstance(activity)
                val width = activity.resources.displayMetrics.widthPixels
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= width) sample *= 2
                val bitmap = BitmapFactory.decodeFile(
                    path,
                    BitmapFactory.Options().apply { inSampleSize = sample },
                ) ?: error("图片解码失败")
                val flags = when (target) {
                    "lock" -> WallpaperManager.FLAG_LOCK
                    "both" -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                    else -> WallpaperManager.FLAG_SYSTEM
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    manager.setBitmap(bitmap, null, true, flags)
                } else {
                    manager.setBitmap(bitmap)
                }
                bitmap.recycle()
            }
            main.post {
                outcome.onSuccess { result.success(true) }
                    .onFailure { result.error("setWallpaper", it.message ?: "设置失败", null) }
            }
        }
    }

    private fun mimeOf(path: String): String {
        val ext = path.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "image/*"
    }

    /** 系统浏览器 / Pixiv App 打开作品页（详情页的「在 Pixiv 打开」）。 */
    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("openUrl", "缺少 url", null)
            return
        }
        runCatching {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }.onSuccess {
            result.success(true)
        }.onFailure {
            result.error("openUrl", it.message, null)
        }
    }

    /** 一次枚举全机图片。字段与桌面端 scan 语义对齐（相对路径用来筛图库根）。 */
    private fun listImages(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.RELATIVE_PATH,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
        )
        val rows = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                rows.add(
                    mapOf(
                        "id" to cursor.getLong(0),
                        "name" to name,
                        // RELATIVE_PATH 自带尾斜杠：trim 掉，Flutter 侧拼路径用
                        "relativePath" to (cursor.getString(2) ?: "").trimEnd('/'),
                        "size" to cursor.getLong(3),
                        "modified" to cursor.getLong(4),
                        "width" to cursor.getInt(5),
                        "height" to cursor.getInt(6),
                    ),
                )
            }
        }
        return rows
    }

    /**
     * 系统缩略图：29+ 走 `loadThumbnail`（MediaProvider 预生成，命中系统缓存时
     * 只要几百微秒）；更老的系统退回 `Thumbnails.getThumbnail`。
     */
    private fun thumbnailBytes(id: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            activity.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Thumbnails.getThumbnail(
                activity.contentResolver,
                id,
                MediaStore.Images.Thumbnails.MINI_KIND,
                null,
            )
        } ?: return null
        return ByteArrayOutputStream(64 * 1024).use { out ->
            // 缩略图本身不大：WebP 质量 85，内存/带宽都比 PNG 省
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 85, out)
            } else {
                @Suppress("DEPRECATION")
                bitmap.compress(Bitmap.CompressFormat.WEBP, 85, out)
            }
            bitmap.recycle()
            out.toByteArray()
        }
    }
}
