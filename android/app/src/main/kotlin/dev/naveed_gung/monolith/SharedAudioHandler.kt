package dev.naveed_gung.monolith

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Copies granted content URIs while the sender's permission is still valid. */
class SharedAudioHandler(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "monolith/shared_audio")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val pending = mutableListOf<Map<String, Any>>()
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "takePending") {
                val delivered = pending.toList()
                pending.clear()
                result.success(delivered)
            } else result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    fun accept(intent: Intent?) {
        val uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        if (uri.scheme != "content") return
        executor.execute {
            var staging: File? = null
            val outcome = try {
                val resolver = activity.contentResolver
                require((resolver.getType(uri) ?: intent?.type ?: "").startsWith("audio/")) {
                    "The shared item is not an audio file."
                }
                val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: "Shared audio.m4a"
                val safe = File(name).name.replace(Regex("[^\\p{L}\\p{N} ._-]"), "_").take(140)
                val extension = safe.substringAfterLast('.', "m4a").lowercase()
                require(extension in setOf("aac", "aiff", "alac", "amr", "flac", "m4a", "mp3", "mp4", "oga", "ogg", "opus", "wav", "weba", "webm")) {
                    "This audio format is not supported."
                }
                val working = File.createTempFile("shared-audio-", ".part", activity.cacheDir)
                staging = working
                val digest = MessageDigest.getInstance("SHA-256")
                resolver.openInputStream(uri)?.use { input ->
                    working.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var count = input.read(buffer)
                        while (count != -1) {
                            if (Thread.currentThread().isInterrupted) throw InterruptedException()
                            digest.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                            count = input.read(buffer)
                        }
                    }
                } ?: error("The sending app did not provide readable audio.")
                require(working.length() > 0) { "The shared audio file is empty." }
                val hash = digest.digest().joinToString("") { "%02x".format(it) }.take(16)
                val base = activity.getExternalFilesDir(null) ?: File(activity.applicationInfo.dataDir, "app_flutter")
                val imports = File(base, "Monolith/Music/Imports").apply { mkdirs() }
                val target = File(imports, "${safe.substringBeforeLast('.', safe)}-shared-$hash.$extension")
                if (!target.exists()) {
                    // Copy to a sibling .part then rename: recovery never sees partial audio.
                    val temporary = File(imports, "${target.name}.part")
                    try {
                        working.copyTo(temporary, overwrite = true)
                        check(temporary.renameTo(target)) { "Could not finish saving shared audio." }
                    } finally { temporary.delete() }
                }
                mapOf<String, Any>("path" to target.path)
            } catch (error: Exception) {
                mapOf<String, Any>("error" to (error.message ?: "Could not import shared audio."))
            } finally { staging?.delete() }
            main.post {
                if (!disposed) {
                    pending.add(outcome)
                    channel.invokeMethod("ready", null)
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
