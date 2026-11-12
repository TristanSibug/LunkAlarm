package online.reeeserve.lunkalarm

import android.content.Context
import android.media.*
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.Settings
import online.reeeserve.lunkalarm.core.*
import java.io.File
import java.util.UUID

class AlarmAudio(private val context: Context, private val repository: AlarmRepository) {
    private val vibrator = context.getSystemService(android.os.Vibrator::class.java)
    private var player: MediaPlayer? = null
    val isPlaying: Boolean get() = player?.isPlaying == true
    private val manager = context.getSystemService(AudioManager::class.java)
    private var focus: AudioFocusRequest? = null
    private var started = 0L
    private var volume = 1f
    private var gradual = false
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    fun play(tone: String, level: Float, fade: Boolean, fallback: Boolean = false, vibrate: Boolean = false) {
        stop()
        val audio = MediaPlayer()
        try {
            audio.setAudioAttributes(attributes)
            try {
                val imported = repository.state.value.sounds.firstOrNull { it.id == tone }
                if (imported != null) audio.setDataSource(File(repository.soundDirectory, imported.filename).absolutePath)
                else context.assets.openFd("sounds/$tone.wav").use { audio.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                audio.prepare()
            } catch (failure: Exception) {
                if (!fallback) throw failure
                audio.reset(); audio.setAudioAttributes(attributes)
                audio.setDataSource(context, Settings.System.DEFAULT_ALARM_ALERT_URI); audio.prepare()
            }
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener({ change ->
                    if (change == AudioManager.AUDIOFOCUS_GAIN) runCatching { player?.start() }
                    else if (change < 0 && change != AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) runCatching { player?.pause() }
                }, Handler(Looper.getMainLooper())).build()
            manager.requestAudioFocus(checkNotNull(focus))
            volume = level; gradual = fade; started = SystemClock.elapsedRealtime()
            audio.isLooping = true
            val initial = if (fade) 0f else volume
            audio.setVolume(initial, initial); audio.start(); player = audio
            if (vibrate) vibrator?.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 400, 600), 0), attributes)
        } catch (failure: Exception) { audio.release(); stop(); throw failure }
    }
    fun updateLevel(level: Float) { volume = level; tick() }
    fun tick() {
        val gain = AlarmTime.gain(volume, SystemClock.elapsedRealtime() - started, gradual)
        runCatching { player?.setVolume(gain, gain) }
    }
    fun stop() {
        vibrator?.cancel()
        player?.release(); player = null
        focus?.let { manager.abandonAudioFocusRequest(it) }; focus = null
    }
}

object SoundImport {
    fun copy(context: Context, repository: AlarmRepository, uri: Uri): ImportedSound {
        val display = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "My ringtone"
        val id = UUID.randomUUID().toString()
        val file = File(repository.soundDirectory, "$id.audio")
        try {
            val input = checkNotNull(context.contentResolver.openInputStream(uri)) { "This file could not be opened." }
            input.use { source -> file.outputStream().use { dest ->
                val buffer = ByteArray(8192); var total = 0
                while (true) {
                    val size = source.read(buffer); if (size < 0) break
                    total += size; require(total <= 2 * 1024 * 1024) { "Choose an audio file smaller than 2 MB." }
                    dest.write(buffer, 0, size)
                }
            } }
            val retriever = MediaMetadataRetriever()
            val duration = try { retriever.setDataSource(file.absolutePath); retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() }
                finally { retriever.release() }
            require(duration != null && duration in 1..30000) { "Choose a supported audio clip no longer than 30 seconds." }
            val sound = ImportedSound(id, display.substringBeforeLast('.').take(80), file.name)
            repository.update { it.copy(sounds = it.sounds + sound) }
            return sound
        } catch (failure: Exception) { file.delete(); throw failure }
    }
}
