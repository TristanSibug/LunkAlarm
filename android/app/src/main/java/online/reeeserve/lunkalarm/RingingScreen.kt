package online.reeeserve.lunkalarm

import android.content.Context
import android.graphics.Typeface
import android.text.*
import android.text.InputType
import android.view.*
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import online.reeeserve.lunkalarm.core.*

@Composable fun RingingScreen(activity: RingingActivity) {
    val repo = activity.graph.repository; val controller = activity.graph.controller
    val state by repo.state.collectAsStateWithLifecycle(); val error by repo.error.collectAsStateWithLifecycle()
    val theme = Themes.find(state.theme)
    SideEffect { activity.applyBars(theme) }
    val session = state.session
    LaunchedEffect(session?.owner, activity.locked) {
        if (session == null) activity.finish()
        else if (!activity.locked) controller.opened()
    }
    BackHandler { activity.moveTaskToBack(true) }
    if (session == null) return
    val alarm = state.alarms.firstOrNull { it.id == session.owner } ?: return
    val challenge = session.challenge
    var code by remember(session.owner, challenge.resets) { mutableStateOf("") }
    var answer by remember(session.owner, challenge.resets) { mutableStateOf("") }
    var hint by remember(session.owner, challenge.resets) { mutableStateOf("") }
    var now by remember { mutableLongStateOf(android.os.SystemClock.elapsedRealtime()) }
    val view = LocalView.current
    LaunchedEffect(Unit) { while (true) { now = android.os.SystemClock.elapsedRealtime(); delay(250) } }
    LunkStyle(theme) {
        Column(Modifier.fillMaxSize().background(theme.background).windowInsetsPadding(WindowInsets.safeDrawing).testTag("ringing-screen")) {
            if (alarm.hasTests && !activity.locked) Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${challenge.secondsLeft(now)}s", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = theme.muted, modifier = Modifier.testTag("challenge-countdown"))
                Spacer(Modifier.weight(1f)); Text("Sound", fontSize = 13.sp, color = theme.text)
                Switch(session.sound, onCheckedChange = { controller.sound(it) }, modifier = Modifier.testTag("challenge-sound"), colors = SwitchDefaults.colors(checkedTrackColor = theme.accent2))
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(painterResource(R.drawable.ic_alarm), null, tint = theme.accent, modifier = Modifier.size(34.dp))
                Text("Good morning.", fontSize = 32.sp, fontWeight = FontWeight.Light, color = theme.text)
                Text(Tones.all.firstOrNull { it.first == alarm.draft.tone }?.second ?: state.sounds.firstOrNull { it.id == alarm.draft.tone }?.name ?: "LunkAlarm", fontSize = 12.sp, color = theme.muted)
                if (alarm.hasTests && activity.locked) {
                    Spacer(Modifier.height(32.dp))
                    Text("Unlock to start your wake-up tests", color = theme.muted, fontSize = 16.sp)
                    AccentButton("Unlock to start", theme, Modifier.testTag("unlock-tests"), click = activity::unlock)
                } else if (challenge.typingPending) {
                    Text("Type this code", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Text(challenge.code, fontSize = 30.sp, fontFamily = FontFamily.Monospace, color = theme.text, modifier = Modifier.testTag("challenge-code"))
                    CodeField(code, challenge.codeLength, theme) { code = it }
                    AccentButton("Check code", theme, Modifier.testTag("check-code")) {
                        when (controller.submit(code, true)) {
                            AnswerResult.CORRECT -> { code = ""; hint = "" }
                            AnswerResult.INCORRECT -> hint = "Match the code exactly, including capital letters."
                            AnswerResult.TIMED_OUT -> { code = ""; hint = "Time’s up. Tests restarted." }
                            else -> Unit
                        }
                    }
                } else if (challenge.remaining > 0) {
                    Text("${challenge.answered} / ${challenge.total} answered", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("math-progress"))
                    Text("${challenge.left} + ${challenge.right}", fontSize = 48.sp, fontWeight = FontWeight.Light, modifier = Modifier.testTag("math-problem"))
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(theme.field).padding(14.dp), contentAlignment = Alignment.Center) {
                        Text(answer.ifEmpty { "Your answer" }, fontSize = 26.sp, color = if (answer.isEmpty()) theme.muted else theme.text, modifier = Modifier.testTag("math-answer"))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("", "0", "⌫")).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { row.forEach { key ->
                                if (key.isEmpty()) Spacer(Modifier.weight(1f).height(56.dp)) else Box(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(14.dp)).background(theme.card)
                                    .clickable {
                                        haptic(view)
                                        if (key == "⌫") answer = answer.dropLast(1)
                                        else {
                                            val value = answer + key
                                            when (controller.submit(value, false)) {
                                                AnswerResult.INCOMPLETE -> answer = value
                                                AnswerResult.CORRECT -> { answer = ""; hint = "" }
                                                AnswerResult.INCORRECT -> { answer = ""; hint = "Try that one again."; haptic(view, true) }
                                                AnswerResult.TIMED_OUT -> { answer = ""; hint = "Time’s up. Tests restarted." }
                                            }
                                        }
                                    }.testTag("key-$key"), contentAlignment = Alignment.Center) {
                                    Text(key, fontSize = 24.sp, fontWeight = FontWeight.Medium)
                                }
                            } }
                        }
                    }
                } else if (!alarm.hasTests) {
                    Spacer(Modifier.height(32.dp))
                    AccentButton("Stop alarm", theme, Modifier.testTag("stop-alarm")) { controller.finish() }
                }
                if (hint.isNotEmpty()) Text(hint, color = theme.accent, fontSize = 12.sp)
            }
        }
        if (error != null) AlertDialog(onDismissRequest = { repo.report(null) }, title = { Text("LunkAlarm") }, text = { Text(error.orEmpty()) },
            confirmButton = { TextButton(onClick = { repo.report(null) }) { Text("OK") } })
    }
}
private class NoPasteEditText(context: Context) : EditText(context) {
    var suppress = false
    override fun onTextContextMenuItem(id: Int): Boolean = if (id == android.R.id.paste || id == android.R.id.pasteAsPlainText || id == android.R.id.copy) false else super.onTextContextMenuItem(id)
    override fun isSuggestionsEnabled() = false
}
@Composable private fun CodeField(text: String, maximum: Int, theme: LunkTheme, change: (String) -> Unit) {
    val latest by rememberUpdatedState(change)
    AndroidView(modifier = Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(14.dp)).background(theme.field).testTag("wake-code"), factory = { context ->
        NoPasteEditText(context).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setSingleLine(true); textSize = 24f; typeface = Typeface.MONOSPACE; gravity = Gravity.CENTER
            setBackgroundColor(android.graphics.Color.TRANSPARENT); isLongClickable = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            contentDescription = "Wake-up code"
            val noMenu = object : ActionMode.Callback {
                override fun onCreateActionMode(mode: ActionMode, menu: Menu) = false
                override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
                override fun onActionItemClicked(mode: ActionMode, item: MenuItem) = false
                override fun onDestroyActionMode(mode: ActionMode) {}
            }
            customSelectionActionModeCallback = noMenu; customInsertionActionModeCallback = noMenu
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(value: Editable?) { if (!suppress) { haptic(this@apply); latest(value.toString()) } }
            })
        }
    }, update = { field ->
        field.setTextColor(theme.text.toArgb())
        field.filters = arrayOf(InputFilter { source, start, end, _, _, _ -> if (end - start > 1) "" else null }, InputFilter.LengthFilter(maximum))
        if (field.text.toString() != text) { field.suppress = true; field.setText(text); field.setSelection(text.length); field.suppress = false }
    })
}
