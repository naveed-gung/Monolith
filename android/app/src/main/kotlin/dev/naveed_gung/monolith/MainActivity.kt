package dev.naveed_gung.monolith

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/// Extends [AudioServiceActivity] (a FlutterActivity subclass) so that:
/// 1. just_audio_background's media session works in the background, and
/// 2. the launcher activity is our own class — configureFlutterEngine runs,
///    registering the monolith/media_import channel (P2 review fix).
class MainActivity : AudioServiceActivity() {

    private var mediaImportHandler: MediaImportHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaImportHandler = MediaImportHandler(this).also { it.attach(flutterEngine) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "monolith/updates").setMethodCallHandler { call, result ->
            if (call.method != "install") {
                result.notImplemented()
            } else try {
                val file = File(call.argument<String>("path") ?: "").canonicalFile
                val allowed1 = File(filesDir, "Updates").canonicalFile
                val allowed2 = File(filesDir.parentFile, "app_flutter/Updates").canonicalFile
                val parent = file.parentFile
                require((parent == allowed1 || parent == allowed2 || file.path.contains("/Updates/")) && file.extension == "apk" && file.isFile) { "Invalid update path" }
                val info = packageManager.getPackageArchiveInfo(file.path, 0)
                require(info?.packageName == packageName) { "This update belongs to another app" }
                val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(null)
            } catch (error: Exception) {
                result.error("install_failed", error.message, null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaImportHandler?.detach()
        mediaImportHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Intercept the SAF export flow first; anything else keeps the
        // default Flutter plugin forwarding behaviour.
        if (mediaImportHandler?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
