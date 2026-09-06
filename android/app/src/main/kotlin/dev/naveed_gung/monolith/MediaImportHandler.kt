package dev.naveed_gung.monolith

import android.media.MediaMetadataRetriever
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Native import/export bridge for Monolith 2.0.
 *
 * Channel: `monolith/media_import`
 *
 * Methods:
 * - `exportToSaf` `{paths: [String], mimeTypes: [String]}` → launches
 *   ACTION_CREATE_DOCUMENT sequentially per file and copies bytes into the
 *   user-chosen destination. Returns `{savedCount: Int, canceled: Bool}`.
 * - `writeToPublicMusic` `{path: String}` → inserts into MediaStore.Audio
 *   (RELATIVE_PATH = Music/Monolith on Q+, legacy public dir best-effort
 *   before Q) so exported audio survives uninstall. Returns `{uri}` or an
 *   error result.
 * - `getPublicMusicDir` → best-effort absolute path of public Music/Monolith,
 *   or null.
 *
 * All file IO runs on a single background executor; results are posted back
 * to the main thread where MethodChannel replies must be sent.
 */
class MediaImportHandler(private val activity: Activity) {

    companion object {
        const val CHANNEL_NAME = "monolith/media_import"
        private const val SAF_REQUEST_CODE = 4711

        private val EXT_TO_MIME = mapOf(
            "mp3" to "audio/mpeg",
            "m4a" to "audio/mp4",
            "mp4" to "audio/mp4",
            "aac" to "audio/aac",
            "flac" to "audio/flac",
            "wav" to "audio/x-wav",
            "ogg" to "audio/ogg",
            "oga" to "audio/ogg",
            "opus" to "audio/ogg",
            "webm" to "audio/webm",
            "weba" to "audio/webm",
            "aiff" to "audio/aiff",
        )

        fun mimeForFileName(name: String): String {
            val dot = name.lastIndexOf('.')
            val ext = if (dot <= 0 || dot == name.length - 1) "" else name.substring(dot + 1).lowercase()
            return EXT_TO_MIME[ext] ?: "application/octet-stream"
        }
    }

    private data class SafJob(val sourcePath: String, val mimeType: String, val fileName: String)

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var safQueue: MutableList<SafJob> = mutableListOf()
    private var currentSafJob: SafJob? = null
    private var safSavedCount = 0
    private var safPendingReply: MethodChannel.Result? = null

    /** Registers the method-channel handlers. Call from configureFlutterEngine. */
    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
            "readAudioMetadata" -> {
                val path = call.argument<String>("path")
                executor.execute {
                    val reader = MediaMetadataRetriever()
                    val metadata = try {
                        reader.setDataSource(path)
                        mapOf("durationMs" to (reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L))
                    } catch (_: Exception) { emptyMap<String, Any>() }
                    finally { reader.release() }
                    Handler(Looper.getMainLooper()).post { result.success(metadata) }
                }
            }
                    "exportToSaf" -> exportToSaf(call, result)
                    "writeToPublicMusic" -> writeToPublicMusic(call, result)
                    "getPublicMusicDir" -> getPublicMusicDir(result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Releases background resources. Call from cleanUpFlutterEngine. */
    fun detach() {
        executor.shutdown()
    }

    // ------------------------------------------------------------------
    // SAF sequential export
    // ------------------------------------------------------------------

    private fun exportToSaf(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        @Suppress("UNCHECKED_CAST")
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()

        val jobs = paths.mapIndexed { index, path ->
            val file = File(path)
            val mime = mimeTypes.getOrNull(index)?.takeIf { it.isNotBlank() }
                ?: mimeForFileName(file.name)
            SafJob(path, mime, file.name)
        }.filter { File(it.sourcePath).exists() }

        if (jobs.isEmpty()) {
            result.success(mapOf("savedCount" to 0, "canceled" to true))
            return
        }

        safQueue = jobs.toMutableList()
        safSavedCount = 0
        safPendingReply = result
        launchNextSafJob()
    }

    private fun launchNextSafJob() {
        if (safQueue.isEmpty()) {
            replySafFinished(canceled = false)
            return
        }
        val job = safQueue.removeAt(0)
        currentSafJob = job
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = job.mimeType
            putExtra(Intent.EXTRA_TITLE, job.fileName)
        }
        activity.startActivityForResult(intent, SAF_REQUEST_CODE)
    }

    /**
     * Returns true when [requestCode] belongs to this handler (the caller
     * must then skip forwarding to super.onActivityResult).
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAF_REQUEST_CODE) return false
        val reply = safPendingReply ?: return true

        val uri = data?.data
        val job = currentSafJob
        if (resultCode != Activity.RESULT_OK || uri == null || job == null) {
            // User cancelled mid-sequence: stop with what was saved so far.
            currentSafJob = null
            mainHandler.post { replySafFinished(canceled = true) }
            return true
        }

        executor.execute {
            val saved = try {
                activity.contentResolver.openOutputStream(uri)?.use { out ->
                    File(job.sourcePath).inputStream().use { input -> input.copyTo(out) }
                    true
                } ?: false
            } catch (_: Exception) {
                false
            }
            if (saved) safSavedCount++
            mainHandler.post {
                currentSafJob = null
                launchNextSafJob()
            }
        }
        return true
    }

    private fun replySafFinished(canceled: Boolean) {
        val reply = safPendingReply
        clearSafState()
        reply?.success(mapOf("savedCount" to safSavedCount, "canceled" to canceled))
    }

    private fun clearSafState() {
        safQueue = mutableListOf()
        currentSafJob = null
        safPendingReply = null
    }

    // ------------------------------------------------------------------
    // Public Music write (survives uninstall)
    // ------------------------------------------------------------------

    private fun writeToPublicMusic(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path is required", null)
            return
        }
        val source = File(path)
        if (!source.exists()) {
            result.error("not_found", "File does not exist: $path", null)
            return
        }

        executor.execute {
            try {
                val displayName = source.name
                val mime = mimeForFileName(displayName)
                val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    insertViaMediaStore(source, displayName, mime)
                } else {
                    copyToLegacyPublicMusic(source, displayName)
                }
                mainHandler.post { result.success(mapOf("uri" to uri.toString())) }
            } catch (e: Exception) {
                mainHandler.post { result.error("write_failed", e.message ?: "write failed", null) }
            }
        }
    }

    private fun insertViaMediaStore(source: File, displayName: String, mime: String): Uri {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/Monolith")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val inserted = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore insert returned null")
        resolver.openOutputStream(inserted)?.use { out ->
            source.inputStream().use { input -> input.copyTo(out) }
        } ?: throw IllegalStateException("Could not open output stream for $inserted")
        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(inserted, values, null, null)
        return inserted
    }

    /** Best-effort pre-Q path; may fail without WRITE_EXTERNAL_STORAGE grant. */
    private fun copyToLegacyPublicMusic(source: File, displayName: String): Uri {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "Monolith",
        )
        if (!dir.exists()) dir.mkdirs()
        val target = uniqueTarget(dir, displayName)
        source.copyTo(target, overwrite = false)
        return Uri.fromFile(target)
    }

    private fun uniqueTarget(dir: File, fileName: String): File {
        var candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot <= 0) fileName else fileName.substring(0, dot)
        val ext = if (dot <= 0) "" else fileName.substring(dot)
        var counter = 1
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($counter)$ext")
            counter++
        }
        return candidate
    }

    // ------------------------------------------------------------------
    // Public music directory query
    // ------------------------------------------------------------------

    private fun getPublicMusicDir(result: MethodChannel.Result) {
        try {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                "Monolith",
            )
            if (!dir.exists()) dir.mkdirs()
            result.success(dir.absolutePath)
        } catch (_: Exception) {
            result.success(null)
        }
    }
}
