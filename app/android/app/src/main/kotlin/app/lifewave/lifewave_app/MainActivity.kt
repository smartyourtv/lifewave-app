package app.lifewave.lifewave_app

import android.content.ContentValues
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max

/// PCM playback sink for the Kokoro voice (v1.1.0). The Dart side
/// synthesizes int16 PCM with sherpa-onnx; this channel is the ONLY
/// audio-out path for it. Contract (app-internal, see voice_service.dart
/// MethodChannelPcmPlayer):
///   "play" { pcm: ByteArray (int16 LE mono), sampleRate: Int }
///     -> completes (null) when the audio has actually finished
///        playing, or early when "stop" intervenes. Same completion
///        semantics flutter_tts gives the speech controller via
///        awaitSpeakCompletion — the controller depends on it.
///   "stop" -> halts the current playback immediately.
/// Writes happen on a background executor; MethodChannel results are
/// always delivered on the main thread.
class MainActivity : FlutterActivity() {
    private val pcmChannelName = "lifewave/pcm_player"
    private val downloadsChannelName = "lifewave/downloads"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pcmExecutor = Executors.newCachedThreadPool()
    private val ioExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var currentTrack: AudioTrack? = null

    @Volatile
    private var stopRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pcmChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val pcm = call.argument<ByteArray>("pcm")
                        val rate = call.argument<Int>("sampleRate")
                        if (pcm == null || rate == null || rate <= 0) {
                            result.error(
                                "bad_args", "play needs pcm bytes and a positive sampleRate", null
                            )
                        } else {
                            pcmExecutor.execute { playBlocking(pcm, rate, result) }
                        }
                    }
                    "stop" -> {
                        stopPlayback()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Crash-report Downloads mirror (v1.1.1): writes a report text
        // file into the PUBLIC Downloads folder. API 29+ goes through
        // MediaStore (no permission needed); older APIs try the public
        // directory directly and report false when the device refuses.
        // Returns Boolean success; never throws back to Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "writeTextFile") {
                    val name = call.argument<String>("name")
                    val contents = call.argument<String>("contents")
                    if (name == null || contents == null) {
                        result.error("bad_args", "writeTextFile needs name and contents", null)
                    } else {
                        ioExecutor.execute {
                            val ok = writeToDownloads(name, contents)
                            mainHandler.post { result.success(ok) }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun writeToDownloads(name: String, contents: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val collection =
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                // Replace an earlier copy of the same report name.
                try {
                    resolver.delete(
                        collection,
                        "${MediaStore.Downloads.DISPLAY_NAME} = ?",
                        arrayOf(name)
                    )
                } catch (_: Exception) {
                    // Deleting a prior copy is best-effort; MediaStore
                    // would otherwise add a "(1)" duplicate.
                }
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS
                    )
                }
                val uri = resolver.insert(collection, values) ?: return false
                resolver.openOutputStream(uri)?.use { out ->
                    out.write(contents.toByteArray(Charsets.UTF_8))
                } ?: return false
                true
            } else {
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                )
                if (!dir.exists()) dir.mkdirs()
                File(dir, name).writeText(contents, Charsets.UTF_8)
                true
            }
        } catch (_: Exception) {
            // Permission refused / no Downloads volume — the report
            // still exists in the app's own store (Dart side contract).
            false
        }
    }

    private fun playBlocking(pcm: ByteArray, sampleRate: Int, result: MethodChannel.Result) {
        stopRequested = false
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        var track: AudioTrack? = null
        try {
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(max(minBuffer, pcm.size))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            currentTrack = track
            track.play()
            var offset = 0
            while (offset < pcm.size && !stopRequested) {
                val n = track.write(pcm, offset, minOf(8192, pcm.size - offset))
                if (n < 0) break
                offset += n
            }
            // Wait until the playback head has consumed every frame we
            // wrote — completion must mean "heard", not "queued". The
            // deadline guarantees the Dart future completes even if a
            // device misreports its head position.
            val totalFrames = pcm.size / 2
            val deadlineMs = System.currentTimeMillis() +
                (totalFrames.toLong() * 1000L / sampleRate) + 3000L
            while (!stopRequested &&
                track.playbackHeadPosition < totalFrames &&
                System.currentTimeMillis() < deadlineMs
            ) {
                Thread.sleep(20)
            }
        } catch (e: Exception) {
            // A playback failure must complete the call, never hang the
            // speech controller; the Dart side reports the utterance as
            // not spoken and keeps the words on screen.
            mainHandler.post {
                result.error("play_failed", e.message, null)
            }
            cleanupTrack(track)
            return
        }
        cleanupTrack(track)
        mainHandler.post { result.success(null) }
    }

    private fun cleanupTrack(track: AudioTrack?) {
        if (track == null) return
        try {
            track.stop()
        } catch (_: Exception) {
            // Already stopped/released — cleanup is best-effort.
        }
        track.release()
        if (currentTrack === track) currentTrack = null
    }

    private fun stopPlayback() {
        stopRequested = true
        val track = currentTrack
        if (track != null) {
            try {
                track.pause()
                track.flush()
            } catch (_: Exception) {
                // Racing a natural completion — nothing to stop.
            }
        }
    }
}
