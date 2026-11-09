package online.reeeserve.lunkalarm

import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.input.nestedscroll.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import online.reeeserve.lunkalarm.core.*
import java.time.*
import java.time.format.DateTimeFormatter
import kotlin.math.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MainScreen(activity: MainActivity) {
    val repo = activity.graph.repository; val controller = activity.graph.controller
    val state by repo.state.collectAsStateWithLifecycle(); val error by repo.error.collectAsStateWithLifecycle()
    val theme = Themes.find(state.theme)
    var alarmsOpen by rememberSaveable { mutableStateOf(false) }
    var themesOpen by remember { mutableStateOf(false) }
    var permissionsOpen by remember { mutableStateOf(false) }
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    val draftSaver = remember { Saver<AlarmDraft?, String>(save = { it?.let { d -> AlarmJson.encode(AppState(draft = d)) } ?: "" }, restore = { if (it.isEmpty()) null else AlarmJson.decode(it).draft }) }
    var editor by rememberSaveable(stateSaver = draftSaver) { mutableStateOf<AlarmDraft?>(null) }
    SideEffect { activity.applyBars(theme) }
    LaunchedEffect(state.session?.owner) {
        if (state.session != null && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            editor = null; AlarmService.start(activity); activity.startActivity(RingingActivity.intent(activity))
        }
    }
    BackHandler(editor != null || alarmsOpen) { if (editor != null) editor = null else alarmsOpen = false }
    LunkStyle(theme) {
        Box(Modifier.fillMaxSize().background(theme.background)) {
            if (theme.glow) Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.radialGradient(
                listOf(androidx.compose.ui.graphics.Color(0xff7c5cff).copy(alpha = .22f), androidx.compose.ui.graphics.Color.Transparent), Offset.Zero, 900f)))
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val revision = activity.permissionRevision
                    val allowed = remember(revision, permissionsOpen) { controller.scheduler.exactAllowed && controller.scheduler.notificationsAllowed }
                    Row(Modifier.weight(1f, fill = false).clip(CircleShape).background(theme.text.copy(alpha = .055f)).clickable { permissionsOpen = true }
                        .padding(horizontal = 10.dp, vertical = 10.dp).testTag("alarm-access"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.size(7.dp).background(if (allowed) androidx.compose.ui.graphics.Color(0xff39dc78) else theme.accent, CircleShape))
                        Text(if (allowed) "Alarms allowed" else "Alarm access", fontSize = 11.sp, color = theme.muted, maxLines = 1)
                    }
                    Spacer(Modifier.weight(1f))
                    Chip("Theme", theme) { themesOpen = true }
                    Chip(if (state.use24Hour) "24h" else "12h", theme) { repo.update { it.copy(use24Hour = !it.use24Hour) } }
                }
                AnimatedContent(alarmsOpen, modifier = Modifier.weight(1f), transitionSpec = {
                    val enter = slideInVertically(tween(350)) { if (targetState) it else -it } + fadeIn(tween(250))
                    val exit = slideOutVertically(tween(350)) { if (targetState) -it else it } + fadeOut(tween(250))
                    enter togetherWith exit
                }, label = "clock-to-alarms") { open ->
                    if (open) SavedAlarmScreen(state, theme, controller, clock = { alarmsOpen = false }, add = {
                        editingId = null; editor = state.draft.copy(name = "", timer = false)
                    }, edit = { record -> editingId = record.id; editor = record.draft })
                    else ClockScreen(state.use24Hour, theme) { alarmsOpen = true }
                }
            }
            editor?.let { draft ->
                Box(Modifier.fillMaxSize().background(theme.background).windowInsetsPadding(WindowInsets.safeDrawing)) {
                    AlarmEditor(draft, editingId, state, theme, activity, change = { editor = it }, close = { editor = null }, permissions = { permissionsOpen = true })
                }
            }
            if (themesOpen) ModalBottomSheet(onDismissRequest = { themesOpen = false }, containerColor = theme.card) {
                Text("Theme", Modifier.padding(horizontal = 24.dp, vertical = 8.dp), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                LazyVerticalGrid(GridCells.Fixed(2), Modifier.heightIn(max = 560.dp).padding(horizontal = 20.dp), contentPadding = PaddingValues(bottom = 24.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(Themes.all, key = { it.id }) { palette ->
                        Column(Modifier.clip(RoundedCornerShape(16.dp)).background(palette.background)
                            .border(1.dp, if (palette.id == state.theme) palette.accent else theme.border, RoundedCornerShape(16.dp))
                            .clickable { repo.update { it.copy(theme = palette.id) } }.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(Modifier.size(16.dp).background(palette.accent, CircleShape)); Box(Modifier.size(16.dp).background(palette.accent2, CircleShape))
                            }
                            Text(palette.name, color = palette.text, fontSize = 13.sp)
                        }
                    }
                }
            }
            if (permissionsOpen) key(activity.permissionRevision) {
                AlertDialog(onDismissRequest = { permissionsOpen = false }, title = { Text("Alarm access") }, text = {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Allow precise alarms and notifications so LunkAlarm can ring and show your alarm while your phone is locked.")
                        TextButton(onClick = activity::alarmPermission, enabled = !controller.scheduler.exactAllowed) { Text(if (controller.scheduler.exactAllowed) "Alarms & reminders allowed" else "Allow alarms & reminders") }
                        TextButton(onClick = activity::requestNotifications, enabled = !controller.scheduler.notificationsAllowed) { Text(if (controller.scheduler.notificationsAllowed) "Notifications allowed" else "Allow notifications") }
                        TextButton(onClick = activity::fullScreenPermission, enabled = !controller.scheduler.fullScreenAllowed) { Text(if (controller.scheduler.fullScreenAllowed) "Full-screen alarms allowed" else "Allow full-screen alarms") }
                        Text("Android controls lock-screen presentation and overall alarm volume.", fontSize = 12.sp, color = theme.muted)
                    }
                }, confirmButton = { TextButton(onClick = { permissionsOpen = false }) { Text("Close") } })
            }
            if (error != null && !permissionsOpen) AlertDialog(onDismissRequest = { repo.report(null) }, title = { Text("LunkAlarm") }, text = { Text(error.orEmpty()) },
                confirmButton = { TextButton(onClick = { repo.report(null) }) { Text("OK") } })
        }
    }
}

@Composable private fun ClockScreen(use24: Boolean, theme: LunkTheme, alarms: () -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val latest by rememberUpdatedState(alarms)
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(500) } }
    BoxWithConstraints(Modifier.fillMaxSize().testTag("big-clock").pointerInput(Unit) {
        var movement = 0f
        detectVerticalDragGestures(onDragStart = { movement = 0f }, onVerticalDrag = { _, dy -> movement += dy },
            onDragEnd = { if (movement < -48.dp.toPx()) latest() })
    }) {
        val date = Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault())
        val display = date.format(DateTimeFormatter.ofPattern(if (use24) "HH:mm" else "h:mm"))
        val size = min(maxWidth.value / (if (display.length > 4) 3.4f else 2.7f), (maxHeight.value - 130) * .5f).coerceIn(48f, 200f)
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(display, fontSize = size.sp, lineHeight = (size * 1.05f).sp, fontWeight = FontWeight.ExtraLight, color = theme.text, letterSpacing = (-size * .035f).sp)
                Column(Modifier.padding(top = (size * .12f).dp)) {
                    Text(date.format(DateTimeFormatter.ofPattern("ss")), fontSize = 22.sp, color = theme.accent)
                    if (!use24) Text(date.format(DateTimeFormatter.ofPattern("a")), fontSize = 17.sp, color = theme.muted)
                }
            }
            Text(date.format(DateTimeFormatter.ofPattern("EEEE, MMMM d")), color = theme.text, fontSize = 17.sp, modifier = Modifier.padding(top = 14.dp))
            Text(ZoneId.systemDefault().id, color = theme.muted, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
            Column(Modifier.padding(top = 28.dp).clickable(onClick = alarms).padding(12.dp).testTag("view-alarms"), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.KeyboardArrowUp, null, tint = theme.muted, modifier = Modifier.size(20.dp))
                Text("Swipe up to view alarms", color = theme.muted, fontSize = 12.sp)
            }
        }
        if (maxHeight > 400.dp) Text("Scheduled by Android. No need to keep this screen open.", color = theme.muted, fontSize = 11.sp,
            modifier = Modifier.align(Alignment.BottomCenter).padding(horizontal = 24.dp, vertical = 18.dp))
    }
}

@Composable private fun SavedAlarmScreen(state: AppState, theme: LunkTheme, controller: AlarmController, clock: () -> Unit, add: () -> Unit, edit: (AlarmRecord) -> Unit) {
    val list = rememberLazyListState()
    val latestClock by rememberUpdatedState(clock)
    var pull by remember { mutableFloatStateOf(0f) }
    val connection = remember { object : NestedScrollConnection {
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (available.y > 0 && list.firstVisibleItemIndex == 0 && list.firstVisibleItemScrollOffset == 0) {
                pull += available.y
                if (pull > 120) { pull = 0f; latestClock() }
            } else if (consumed.y < 0) pull = 0f
            return Offset.Zero
        }
    } }
    Box(Modifier.fillMaxSize().nestedScroll(connection).testTag("your-alarms")) {
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 110.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    TextButton(onClick = clock, contentPadding = PaddingValues(0.dp)) { Icon(Icons.Default.KeyboardArrowDown, null, tint = theme.muted); Text("Clock", color = theme.muted) }
                    Text("Your alarms", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = theme.text, modifier = Modifier.testTag("alarms-heading"))
                    val next = state.alarms.filter { it.enabled && it.error == null }.minByOrNull { it.target }
                    Text(next?.let { "Next alarm " + Instant.ofEpochMilli(it.target).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(if (state.use24Hour) "MMM d, HH:mm" else "MMM d, h:mm a")) }
                        ?: "No upcoming alarms", fontSize = 14.sp, color = theme.muted)
                }
            }
            if (state.alarms.isEmpty()) item { Text("No alarms yet. Tap + to add one.", color = theme.muted, modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp)) }
            items(state.alarms.sortedBy { it.target }, key = { it.id }) { record ->
                AlarmCardRow(record, state.use24Hour, theme, controller, edit)
            }
        }
        FloatingActionButton(onClick = add, modifier = Modifier.align(Alignment.BottomEnd).padding(24.dp).testTag("new-alarm"),
            shape = CircleShape, containerColor = theme.accent2, contentColor = theme.onAccent) { Icon(Icons.Default.Add, "New alarm", Modifier.size(30.dp)) }
    }
}

@Composable private fun AlarmCardRow(alarm: AlarmRecord, use24: Boolean, theme: LunkTheme, controller: AlarmController, edit: (AlarmRecord) -> Unit) {
    var offset by remember { mutableFloatStateOf(0f) }; var width by remember { mutableFloatStateOf(350f) }
    var dragging by remember { mutableStateOf(false) }; var armed by remember { mutableStateOf(false) }; var menu by remember { mutableStateOf(false) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val scope = rememberCoroutineScope(); val view = LocalView.current
    val rendered by animateFloatAsState(offset, if (dragging) snap() else tween(180), label = "delete-offset")
    LaunchedEffect(alarm.id) { if (alarm.draft.timer) while (true) { now = System.currentTimeMillis(); delay(500) } }
    fun remove() { scope.launch { offset = -width; delay(180); if (controller.remove(alarm)) haptic(view, true) else offset = 0f } }
    Box(Modifier.fillMaxWidth().clipToBounds().onSizeChanged { width = it.width.toFloat() }
        .pointerInput(alarm.id, alarm.active) {
            if (!alarm.active) detectHorizontalDragGestures(onDragStart = { dragging = true }, onDragCancel = { dragging = false; offset = if (offset < -40.dp.toPx()) -82.dp.toPx() else 0f },
                onDragEnd = { dragging = false; if (-offset >= width * .65f) remove() else offset = if (offset < -40.dp.toPx()) -82.dp.toPx() else 0f; armed = false }) { change, amount ->
                change.consume(); offset = (offset + amount).coerceIn(-width, 0f)
                val next = -offset >= width * .65f; if (next && !armed) haptic(view, true); armed = next
            }
        }.semantics { customActions = if (alarm.active) emptyList() else listOf(CustomAccessibilityAction("Delete") { controller.remove(alarm) }, CustomAccessibilityAction("Duplicate") { controller.duplicate(alarm) }) }) {
        if (offset < 0) IconButton(onClick = { remove() }, modifier = Modifier.align(Alignment.CenterEnd).padding(end = 15.dp).size(52.dp).background(androidx.compose.ui.graphics.Color(0xffff3b49), CircleShape).testTag("swipe-delete-${alarm.id}")) {
            Icon(Icons.Default.Delete, "Delete ${alarm.label}", tint = androidx.compose.ui.graphics.Color.White)
        }
        Column(Modifier.fillMaxWidth().offset { IntOffset(rendered.roundToInt(), 0) }.clip(RoundedCornerShape(18.dp)).background(theme.card)
            .border(1.dp, theme.border, RoundedCornerShape(18.dp)).clickable(enabled = !alarm.active && !dragging && offset == 0f) { edit(alarm) }
            .testTag("alarm-${alarm.id}").padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    if (alarm.draft.name.isNotEmpty() || alarm.draft.timer) Text(alarm.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val label = if (alarm.draft.timer) AlarmTime.duration(alarm.remaining(now, SystemClock.elapsedRealtime(), controller.scheduler.boot)) else
                        "%02d:%02d".format(alarm.draft.hour, alarm.draft.minute).let { _ -> LocalTime.of(alarm.draft.hour, alarm.draft.minute).format(DateTimeFormatter.ofPattern(if (use24) "HH:mm" else "h:mm a")) }
                    Text(label, fontSize = 32.sp, fontWeight = FontWeight.Light, color = if (alarm.enabled) theme.text else theme.muted)
                    Text((if (alarm.draft.timer) "Countdown" else AlarmTime.daysLabel(alarm.draft.days)) + (if (alarm.draft.typing) "   Typing" else "") + (if (alarm.draft.mathCount > 0) "   Math · ${alarm.draft.mathCount}" else ""), color = theme.muted, fontSize = 11.sp)
                }
                if (!alarm.draft.timer) Switch(checked = alarm.enabled, onCheckedChange = { controller.enable(alarm, it) }, enabled = !alarm.active,
                    colors = SwitchDefaults.colors(checkedTrackColor = theme.accent2, checkedThumbColor = androidx.compose.ui.graphics.Color.White), modifier = Modifier.testTag("enabled-${alarm.id}"))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (alarm.draft.timer) Text("Rings at " + Instant.ofEpochMilli(alarm.target).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(if (use24) "HH:mm" else "h:mm a")), color = theme.muted, fontSize = 11.sp, modifier = Modifier.weight(1f))
                else Row(Modifier.weight(1f)) { (1..7).forEach { day -> Text(listOf("S", "M", "T", "W", "T", "F", "S")[day - 1], fontSize = 11.sp,
                    color = if (day in alarm.draft.days) theme.accent else theme.muted, modifier = Modifier.weight(1f)) } }
                Box {
                    IconButton(onClick = { menu = true }, enabled = !alarm.active, modifier = Modifier.size(40.dp, 32.dp).testTag("options-${alarm.id}")) { Icon(Icons.Default.MoreVert, "Options for ${alarm.label}", tint = theme.text) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; controller.remove(alarm) })
                        DropdownMenuItem(text = { Text("Duplicate") }, onClick = { menu = false; controller.duplicate(alarm) })
                    }
                }
            }
            alarm.error?.let { Text(it, fontSize = 12.sp, color = theme.accent) }
            if (alarm.active) TextButton(onClick = { view.context.startActivity(RingingActivity.intent(view.context)) }) { Text("Finish wake-up tests") }
        }
    }
}
