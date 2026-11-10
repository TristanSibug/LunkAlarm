package online.reeeserve.lunkalarm

import android.app.Application
import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.AtomicFile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import online.reeeserve.lunkalarm.core.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class LunkAlarmApplication : Application() {
    val repository by lazy { AlarmRepository(this) }
    val controller by lazy { AlarmController(this, repository) }
    override fun onCreate() { super.onCreate(); repository }
}
val Context.graph get() = applicationContext as LunkAlarmApplication

class AlarmRepository(context: Context) {
    private val storage = context.createDeviceProtectedStorageContext()
    val soundDirectory: File = File(storage.filesDir, "sounds").apply { mkdirs() }
    private val file = AtomicFile(File(storage.filesDir, "alarms.json"))
    var readOnly = false; private set
    private val errors = MutableStateFlow<String?>(null)
    val error = errors.asStateFlow()
    private val current = MutableStateFlow(load())
    val state = current.asStateFlow()
    private fun load(): AppState = try {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) AppState()
        else AlarmJson.decode(file.openRead().use { it.readBytes().toString(Charsets.UTF_8) })
    } catch (error: Exception) {
        readOnly = true
        errors.value = "Saved alarms could not be read. The file has been left untouched. ${error.localizedMessage}"
        AppState()
    }
    @Synchronized fun update(change: (AppState) -> AppState) {
        check(!readOnly) { "Saved data is protected. Changes are disabled because it could not be read." }
        val next = change(current.value)
        val bytes = AlarmJson.encode(next).toByteArray(Charsets.UTF_8)
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (failure: Exception) { file.failWrite(stream); throw failure }
        current.value = next
    }
    fun report(message: String?) { errors.value = message }
    fun resetForTests(context: Context) {
        check(context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
        file.delete(); readOnly = false; current.value = AppState(); errors.value = null
    }
}

object AlarmJson {
    private fun JSONObject.optionalString(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
    private fun draft(d: AlarmDraft) = JSONObject().apply {
        put("timer", d.timer); put("name", d.name); put("hour", d.hour); put("minute", d.minute); put("seconds", d.seconds)
        put("days", JSONArray(d.days.sorted())); put("tone", d.tone); put("volume", d.volume.toDouble()); put("gradual", d.gradual)
        put("typing", d.typing); put("codeLength", d.codeLength); put("typingSeconds", d.typingSeconds)
        put("mathCount", d.mathCount); put("mathSeconds", d.mathSeconds)
        put("nativeMathKeyboard", d.nativeMathKeyboard); put("puzzle", d.puzzle); put("puzzlePieces", d.puzzlePieces); put("puzzleSeconds", d.puzzleSeconds)
    }
    private fun draft(j: JSONObject): AlarmDraft = AlarmDraft(j.getBoolean("timer"), j.getString("name"), j.getInt("hour"), j.getInt("minute"),
        j.getInt("seconds"), j.getJSONArray("days").let { a -> (0 until a.length()).map { a.getInt(it) }.toSet() },
        j.getString("tone"), j.getDouble("volume").toFloat(), j.getBoolean("gradual"), j.getBoolean("typing"),
        j.getInt("codeLength"), WakeTimers.nearest(j.getInt("typingSeconds"), WakeTimers.typing), j.getInt("mathCount"), WakeTimers.nearest(j.getInt("mathSeconds"), WakeTimers.math), j.optBoolean("nativeMathKeyboard", false),
        j.optBoolean("puzzle", false), j.optInt("puzzlePieces", 8), WakeTimers.nearest(j.optInt("puzzleSeconds", 30), WakeTimers.puzzle)).also { it.validate() }
    private fun challenge(c: WakeChallenge) = JSONObject().apply {
        put("typing", c.typing); put("total", c.total); put("codeLength", c.codeLength); put("typingSeconds", c.typingSeconds); put("mathSeconds", c.mathSeconds)
        put("code", c.code); put("typingPending", c.typingPending); put("remaining", c.remaining); put("left", c.left); put("right", c.right)
        put("deadline", c.deadline); put("resets", c.resets)
        put("puzzle", c.puzzle); put("puzzlePieces", c.puzzlePieces); put("puzzleSeconds", c.puzzleSeconds); put("puzzleSeed", c.puzzleSeed)
        put("placedPieces", JSONArray(c.placedPieces.sorted()))
    }
    private fun challenge(j: JSONObject) = WakeChallenge(j.getBoolean("typing"), j.getInt("total"), j.getInt("codeLength"), WakeTimers.nearest(j.getInt("typingSeconds"), WakeTimers.typing),
        WakeTimers.nearest(j.getInt("mathSeconds"), WakeTimers.math), j.getString("code"), j.getBoolean("typingPending"), j.getInt("remaining"), j.getInt("left"), j.getInt("right"),
        j.getLong("deadline"), j.getInt("resets"), j.optBoolean("puzzle", false), j.optInt("puzzlePieces", 8),
        WakeTimers.nearest(j.optInt("puzzleSeconds", 30), WakeTimers.puzzle), j.optLong("puzzleSeed", 0), j.optJSONArray("placedPieces")?.let { a -> (0 until a.length()).map { a.getInt(it) }.toSet() } ?: emptySet()).also {
        require(it.puzzlePieces in 6..10 && it.puzzleSeconds in 15..40 && it.placedPieces.all { id -> id in 0 until it.puzzlePieces })
        require(it.total in 0..8 && it.remaining in 0..it.total && it.codeLength in 4..10 && it.code.length == it.codeLength)
        require(it.typingSeconds in WakeTimers.typing && it.mathSeconds in WakeTimers.math && it.left in 1..20 && it.right in 1..20)
    }
    fun encode(state: AppState): String = JSONObject().apply {
        put("version", 1); put("theme", state.theme); put("use24Hour", state.use24Hour); put("draft", draft(state.draft))
        put("alarms", JSONArray(state.alarms.map { alarm -> JSONObject().apply {
            put("id", alarm.id); put("draft", draft(alarm.draft)); put("target", alarm.target); put("elapsedTarget", alarm.elapsedTarget)
            put("boot", alarm.boot); put("enabled", alarm.enabled); put("active", alarm.active); put("error", alarm.error)
        } }))
        put("sounds", JSONArray(state.sounds.map { JSONObject().put("id", it.id).put("name", it.name).put("filename", it.filename) }))
        state.session?.let { put("session", JSONObject().put("owner", it.owner).put("challenge", challenge(it.challenge)).put("sound", it.sound).put("opened", it.opened).put("boot", it.boot)) }
    }.toString()
    fun decode(text: String): AppState {
        val j = JSONObject(text); require(j.getInt("version") == 1) { "Unsupported alarm data version." }
        val alarms = j.getJSONArray("alarms").objects().map {
            AlarmRecord(it.getString("id"), draft(it.getJSONObject("draft")), it.getLong("target"), it.getLong("elapsedTarget"),
                it.getInt("boot"), it.getBoolean("enabled"), it.getBoolean("active"), it.optionalString("error"))
        }
        val sounds = j.getJSONArray("sounds").objects().map { ImportedSound(it.getString("id"), it.getString("name"), it.getString("filename")) }
        require(alarms.map { it.id }.distinct().size == alarms.size)
        require(sounds.map { it.id }.distinct().size == sounds.size && sounds.all { it.filename == File(it.filename).name && !it.filename.contains('\\') && it.filename !in listOf("", ".", "..") })
        val session = j.optJSONObject("session")?.let { AlarmSession(it.getString("owner"), challenge(it.getJSONObject("challenge")), it.getBoolean("sound"), it.getBoolean("opened"), it.optInt("boot", -1)) }
        require(session == null || alarms.any { it.id == session.owner && it.active })
        return AppState(j.getString("theme"), j.getBoolean("use24Hour"), draft(j.getJSONObject("draft")), alarms, sounds, session)
    }
}
