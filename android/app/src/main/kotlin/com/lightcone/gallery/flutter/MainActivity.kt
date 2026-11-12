package com.lightcone.gallery.flutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var mediaChannel: MediaStoreChannel? = null
    private var updateChannel: UpdateChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaChannel = MediaStoreChannel(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.attach()
        }
        updateChannel = UpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.attach()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mediaChannel?.onPermissionResult(requestCode, grantResults)
    }

    @Deprecated("Flutter 的 SAF 选择仍走旧回调")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        mediaChannel?.onActivityResult(requestCode, resultCode, data)
    }
}
