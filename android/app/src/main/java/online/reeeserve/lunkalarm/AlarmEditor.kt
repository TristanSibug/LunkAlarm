package online.reeeserve.lunkalarm

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.*
import online.reeeserve.lunkalarm.core.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AlarmEditor(draft: AlarmDraft, editingId: String?, state: AppState, theme: LunkTheme, activity: MainActivity,
    change: (AlarmDraft) -> Unit, close: () -> Unit, permissions: () -> Unit) {
    val repo = activity.graph.repository; val controller = activity.graph.controller
    var sheet by remember { mutableStateOf<String?>(null) }
    var testsExpanded by remember { mutableStateOf(true) }
    var previewing by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val preview = remember { AlarmAudio(activity, repo) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val latest by rememberUpdatedState(change)
    val currentDraft by rememberUpdatedState(draft)
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            importing = true
            try {
                val sound = withContext(Dispatchers.IO) { SoundImport.copy(activity, repo, uri) }
                latest(currentDraft.copy(tone = sound.id))
            } catch (failure: Exception) { repo.report(failure.localizedMessage ?: "Could not import that sound.") }
            finally { importing = false }
        }
    }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) { preview.stop(); previewing = false } }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); preview.stop() }
    }
    LaunchedEffect(previewing, draft.tone, draft.volume, draft.gradual) {
        if (previewing) {
            try {
                preview.play(draft.tone, draft.volume, draft.gradual)
                repeat(if (draft.gradual) 48 else 24) { preview.tick(); delay(250) }
            } catch (failure: Exception) { repo.report(failure.localizedMessage ?: "Could not preview this sound.") }
            finally { preview.stop(); previewing = false }
        } else preview.stop()
    }
    Column(Modifier.fillMaxSize().background(theme.background).imePadding().testTag("alarm-editor")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).background(theme.card).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.size(40.dp))
            Text(if (editingId == null) "New alarm" else "Edit alarm", Modifier.weight(1f), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = theme.text,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            IconButton(onClick = close, modifier = Modifier.testTag("close-editor")) { Icon(Icons.Default.Close, "Close alarm editor", tint = theme.accent) }
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("editor-form"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            if (!draft.timer) item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionLabel("Alarm name", theme)
                    OutlinedTextField(value = draft.name, onValueChange = { change(draft.copy(name = it.take(120))) }, placeholder = { Text("Alarm name (optional)", fontSize = 14.sp) },
                        singleLine = true, modifier = Modifier.fillMaxWidth().testTag("alarm-name"), shape = RoundedCornerShape(12.dp))
                }
            }
            item {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(theme.field).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf(false to "At a time", true to "In how long").forEach { (timer, label) ->
                        val enabled = editingId == null || draft.timer == timer
                        Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (draft.timer == timer) theme.text.copy(alpha = .13f) else androidx.compose.ui.graphics.Color.Transparent)
                            .clickable(enabled = enabled) { change(draft.copy(timer = timer)) }.padding(vertical = 13.dp).testTag(if (timer) "mode-timer" else "mode-time"), contentAlignment = Alignment.Center) {
                            Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (draft.timer == timer) theme.text else theme.muted.copy(alpha = if (enabled) 1f else .5f))
                        }
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel(if (draft.timer) "Ring in" else "Ring at", theme)
                    if (draft.timer) {
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(theme.field).padding(vertical = 10.dp)) {
                            listOf(Triple("Hours", 3600, 100), Triple("Minutes", 60, 60), Triple("Seconds", 1, 60)).forEach { (label, unit, modulus) ->
                                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(label.uppercase(), fontSize = 9.sp, color = theme.muted, letterSpacing = .7.sp)
                                    Wheel(draft.seconds / unit % modulus, 0 until modulus, theme, "duration-${label.lowercase()}", Modifier.fillMaxWidth(),
                                        labels = (0 until modulus).map { if (unit == 3600) it.toString() else "%02d".format(it) }) { value ->
                                        change(draft.copy(seconds = draft.seconds + (value - draft.seconds / unit % modulus) * unit))
                                    }
                                }
                            }
                        }
                        DurationPresets(theme) { change(draft.copy(seconds = it * 60)) }
                    } else {
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(theme.field).padding(horizontal = 10.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            val displayed = if (state.use24Hour) draft.hour else if (draft.hour % 12 == 0) 12 else draft.hour % 12
                            Wheel(displayed, if (state.use24Hour) 0..23 else 1..12, theme, "time-hour", Modifier.weight(1f)) { value ->
                                val crossing = !state.use24Hour && ((displayed == 11 && value == 12) || (displayed == 12 && value == 11))
                                val pm = (draft.hour >= 12) xor crossing
                                change(draft.copy(hour = if (state.use24Hour) value else value % 12 + if (pm) 12 else 0))
                            }
                            Text(":", color = theme.muted, fontSize = 24.sp)
                            Wheel(draft.minute, 0..59, theme, "time-minute", Modifier.weight(1f), (0..59).map { "%02d".format(it) }) { change(draft.copy(minute = it)) }
                            if (!state.use24Hour) Wheel(if (draft.hour >= 12) 1 else 0, 0..1, theme, "time-period", Modifier.weight(.8f), listOf("AM", "PM")) { change(draft.copy(hour = draft.hour % 12 + it * 12)) }
                        }
                    }
                }
            }
            if (!draft.timer) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SectionLabel("Repeat", theme); Spacer(Modifier.weight(1f))
                        TextButton(onClick = { change(draft.copy(days = if (draft.days.size == 7) emptySet() else (1..7).toSet())) }, modifier = Modifier.testTag("daily-repeat")) {
                            if (draft.days.size == 7) Icon(Icons.Default.Check, null, Modifier.size(16.dp))
                            Text("Daily", fontSize = 13.sp)
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        (1..7).forEach { day ->
                            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (day in draft.days) theme.accent else theme.field)
                                .clickable { change(draft.copy(days = if (day in draft.days) draft.days - day else draft.days + day)) }.padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                                Text(listOf("S", "M", "T", "W", "T", "F", "S")[day - 1], color = if (day in draft.days) theme.onAccent else theme.muted, fontSize = 14.sp)
                            }
                        }
                    }
                    Text(AlarmTime.daysLabel(draft.days), color = theme.muted, fontSize = 12.sp)
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("Ringtone", theme)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(theme.field).border(1.dp, theme.border, RoundedCornerShape(12.dp))
                            .clickable { sheet = "tones" }.padding(12.dp).testTag("ringtone-picker"), verticalAlignment = Alignment.CenterVertically) {
                            Text(Tones.all.firstOrNull { it.first == draft.tone }?.second ?: state.sounds.firstOrNull { it.id == draft.tone }?.name ?: "Choose a sound", modifier = Modifier.weight(1f), fontSize = 13.sp, maxLines = 1)
                            Icon(Icons.Default.KeyboardArrowDown, null, Modifier.size(18.dp), tint = theme.muted)
                        }
                        Chip(if (previewing) "Stop" else "Preview", theme) { previewing = !previewing }
                    }
                }
            }
            item { VolumeControls(draft, theme, change) { sheet = "sound-check" } }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(Modifier.fillMaxWidth().clickable { testsExpanded = !testsExpanded }.padding(vertical = 6.dp).testTag("wake-tests"), verticalAlignment = Alignment.CenterVertically) {
                        SectionLabel("Wake-up tests", theme); Spacer(Modifier.weight(1f))
                        Icon(if (testsExpanded) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowRight, null, tint = theme.muted, modifier = Modifier.size(18.dp))
                    }
                    if (testsExpanded) {
                        WakeToggle("Typing test", "Retype a random code", draft.typing, theme, "typing-enabled") { change(draft.copy(typing = it)) }
                        if (draft.typing) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            TestWheel("Length of code", draft.codeLength, 4..10, theme, "typing-length", Modifier.weight(1f)) { change(draft.copy(codeLength = it)) }
                            TestWheel("Timer · seconds", draft.typingSeconds, 15..30, theme, "typing-timer", Modifier.weight(1f)) { change(draft.copy(typingSeconds = it)) }
                        }
                        WakeToggle("Math test", "Solve addition problems", draft.mathCount > 0, theme, "math-enabled") { change(draft.copy(mathCount = if (it) 3 else 0)) }
                        if (draft.mathCount > 0) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            TestWheel("How many problems?", draft.mathCount, 1..8, theme, "math-count", Modifier.weight(1f)) { change(draft.copy(mathCount = it)) }
                            TestWheel("Timer per question · seconds", draft.mathSeconds, 5..12, theme, "math-timer", Modifier.weight(1f)) { change(draft.copy(mathSeconds = it)) }
                        }
                    }
                }
            }
        }
        AccentButton(if (editingId == null) "Add alarm" else "Save changes", theme, Modifier.padding(horizontal = 20.dp, vertical = 12.dp).testTag("save-alarm"), enabled = !repo.readOnly && !importing) {
            if (!controller.scheduler.exactAllowed || !controller.scheduler.notificationsAllowed) permissions()
            else if (controller.save(draft, editingId)) close()
        }
    }
    if (sheet != null) ModalBottomSheet(onDismissRequest = { sheet = null; previewing = false }, containerColor = theme.card,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        when (sheet) {
            "tones" -> {
                Text("Ringtone", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
                LazyColumn(Modifier.heightIn(max = 560.dp), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { ToneRow("Use my own file", false, theme) { sheet = null; importer.launch(arrayOf("audio/*")) } }
                    item { ToneRow("Find more ringtones online", false, theme) { sheet = "online" } }
                    item { HorizontalDivider(Modifier.padding(vertical = 8.dp), color = theme.border) }
                    items(Tones.all, key = { it.first }) { (id, name) -> ToneRow(name, draft.tone == id, theme) { change(draft.copy(tone = id)); sheet = null; previewing = false } }
                    items(state.sounds, key = { it.id }) { sound -> ToneRow(sound.name, draft.tone == sound.id, theme) { change(draft.copy(tone = sound.id)); sheet = null; previewing = false } }
                }
            }
            "online" -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Find more ringtones", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                Text("Download a sound you like, then return to Ringtone → Use my own file.", color = theme.muted, fontSize = 13.sp)
                listOf(Triple("Mixkit", "Free alarm sounds", "https://mixkit.co/free-sound-effects/alarm/"),
                    Triple("Pixabay", "Free sound effects", "https://pixabay.com/sound-effects/search/alarm/"),
                    Triple("Zedge", "Popular phone ringtones", "https://www.zedge.net/find/ringtones/alarm")).forEach { (name, description, url) ->
                    ToneRow("$name  ·  $description", false, theme) { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                }
                Text("Audio files up to 2 MB and 30 seconds are copied to app storage.", color = theme.muted, fontSize = 12.sp)
                Spacer(Modifier.height(16.dp))
            }
            "sound-check" -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                Text("Check your alarm sound", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                VolumeControls(draft, theme, change)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(onClick = { previewing = !previewing }, modifier = Modifier.weight(1f).heightIn(min = 60.dp)) { Text(if (previewing) "Stop preview" else "Preview sound", fontSize = 12.sp) }
                    OutlinedButton(onClick = {
                        if (!controller.scheduler.exactAllowed || !controller.scheduler.notificationsAllowed) { sheet = null; permissions() }
                        else if (controller.save(draft.copy(timer = true, seconds = 5, typing = false, mathCount = 0, name = ""), rememberDraft = false)) { sheet = null; previewing = false }
                    }, modifier = Modifier.weight(1f).heightIn(min = 60.dp).testTag("test-five-seconds")) { Text("Test a 5-second alarm", fontSize = 12.sp) }
                }
                Text("Start the test, then lock your phone to check the sound and gradual increase. Overall loudness uses your Android alarm volume.", color = theme.muted, fontSize = 12.sp)
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}
@Composable private fun ToneRow(name: String, selected: Boolean, theme: LunkTheme, click: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(theme.text.copy(alpha = .045f)).clickable(onClick = click).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(name, fontSize = 14.sp, color = theme.text, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Default.Check, "Selected", tint = theme.accent, modifier = Modifier.size(20.dp))
    }
}
@Composable private fun VolumeControls(draft: AlarmDraft, theme: LunkTheme, change: (AlarmDraft) -> Unit, check: (() -> Unit)? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row { SectionLabel("Alarm volume", theme); Spacer(Modifier.weight(1f)); Text("${(draft.volume * 100).toInt()}%", color = theme.muted, fontSize = 12.sp) }
        Slider(value = draft.volume, onValueChange = { change(draft.copy(volume = it)) }, valueRange = .1f..1f, steps = 17, modifier = Modifier.testTag("alarm-volume"))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Gradually increase volume", fontSize = 13.sp, modifier = Modifier.weight(1f))
            Switch(draft.gradual, onCheckedChange = { change(draft.copy(gradual = it)) }, colors = SwitchDefaults.colors(checkedTrackColor = theme.accent2))
        }
        check?.let { TextButton(onClick = it, contentPadding = PaddingValues(0.dp)) { Text("Check alarm sound", color = theme.accent, fontSize = 13.sp) } }
    }
}
@Composable private fun WakeToggle(title: String, description: String, selected: Boolean, theme: LunkTheme, tag: String, change: (Boolean) -> Unit) {
    HorizontalDivider(color = theme.border)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(description, fontSize = 12.sp, color = theme.muted)
        }
        Switch(selected, onCheckedChange = change, modifier = Modifier.testTag(tag), colors = SwitchDefaults.colors(checkedTrackColor = theme.accent2))
    }
}
@Composable private fun TestWheel(title: String, value: Int, range: IntRange, theme: LunkTheme, tag: String, modifier: Modifier, change: (Int) -> Unit) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, fontSize = 11.sp, color = theme.muted, modifier = Modifier.heightIn(min = 32.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Wheel(value, range, theme, tag, Modifier.fillMaxWidth(), change = change)
    }
}
@Composable private fun DurationPresets(theme: LunkTheme, choose: (Int) -> Unit) {
    val choices = listOf("5 min" to 5, "10 min" to 10, "30 min" to 30, "1 hour" to 60)
    val measurer = rememberTextMeasurer(); val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        var width = 0.dp
        val visible = choices.takeWhile { (label, _) ->
            val textWidth = with(density) { measurer.measure(label, TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold)).size.width.toDp() }
            width += textWidth + 24.dp + if (width > 0.dp) 6.dp else 0.dp
            width <= maxWidth
        }.ifEmpty { choices.take(1) }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { visible.forEach { (label, minutes) ->
            Box(Modifier.weight(1f).clip(CircleShape).background(theme.text.copy(alpha = .06f)).border(1.dp, theme.border, CircleShape)
                .clickable { choose(minutes) }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
        } }
    }
}
