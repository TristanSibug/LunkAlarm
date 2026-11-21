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
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import online.reeeserve.lunkalarm.core.*
import java.time.*
import java.time.format.DateTimeFormatter
import kotlin.math.*

private enum class HomePage { ABOUT, CLOCK, ALARMS }

private enum class ClockFont(val id: String, val title: String, val family: FontFamily, val weight: FontWeight) {
    SYSTEM("system", "System Light", FontFamily.Default, FontWeight.ExtraLight),
    ROUNDED("rounded", "Rounded", FontFamily(Font(R.font.quicksand)), FontWeight.Normal),
    SERIF("serif", "Serif", FontFamily.Serif, FontWeight.Normal),
    MONOSPACED("monospaced", "Monospaced", FontFamily.Monospace, FontWeight.Normal)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MainScreen(activity: MainActivity) {
    val repo = activity.graph.repository; val controller = activity.graph.controller
    val state by repo.state.collectAsStateWithLifecycle(); val error by repo.error.collectAsStateWithLifecycle()
    val theme = Themes.find(state.theme)
    val clockFont = ClockFont.entries.firstOrNull { it.id == state.clockFontId } ?: ClockFont.SYSTEM
    var page by rememberSaveable { mutableStateOf(HomePage.CLOCK) }
    var themesOpen by remember { mutableStateOf(false) }
    var clockFontsOpen by remember { mutableStateOf(false) }
    var permissionsOpen by rememberSaveable { mutableStateOf(activity.offerAlarmSetup) }
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    val draftSaver = remember { Saver<AlarmDraft?, String>(save = { it?.let { d -> AlarmJson.encode(AppState(draft = d)) } ?: "" }, restore = { if (it.isEmpty()) null else AlarmJson.decode(it).draft }) }
    var editor by rememberSaveable(stateSaver = draftSaver) { mutableStateOf<AlarmDraft?>(null) }
    fun showClock() { page = HomePage.CLOCK }
    SideEffect { activity.applyBars(theme) }
    LaunchedEffect(state.session?.owner) {
        if (state.session != null && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            editor = null
            themesOpen = false
            clockFontsOpen = false
            AlarmService.start(activity)
            activity.startActivity(RingingActivity.intent(activity))
        }
    }
    BackHandler(editor != null || page != HomePage.CLOCK) { if (editor != null) editor = null else showClock() }
    LunkStyle(theme) {
        Box(Modifier.fillMaxSize().background(theme.background)) {
            if (theme.id !in listOf("oled", "dark")) Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.radialGradient(
                listOf(theme.accent.copy(alpha = if (theme.light) .09f else .18f), androidx.compose.ui.graphics.Color.Transparent), Offset.Zero, 900f)))
            Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                AnimatedContent(page, modifier = Modifier.fillMaxSize(), transitionSpec = {
                    val direction = if (targetState.ordinal > initialState.ordinal) 1 else -1
                    val enter = slideInVertically(tween(350)) { it * direction } + fadeIn(tween(250))
                    val exit = slideOutVertically(tween(350)) { -it * direction } + fadeOut(tween(250))
                    enter togetherWith exit
                }, label = "clock-pages") { visiblePage ->
                    when (visiblePage) {
                        HomePage.ABOUT -> AboutScreen(theme, state.use24Hour, clockFont, clock = ::showClock,
                            chooseTheme = { themesOpen = true }, chooseFont = { clockFontsOpen = true },
                            toggleFormat = { repo.update { it.copy(use24Hour = !it.use24Hour) } })
                        HomePage.CLOCK -> ClockScreen(state.use24Hour, theme, clockFont,
                            alarms = { page = HomePage.ALARMS }, about = { page = HomePage.ABOUT })
                        HomePage.ALARMS -> SavedAlarmScreen(state, theme, controller, clock = ::showClock, add = { timer ->
                            editingId = null
                            editor = state.draft.copy(name = "", timer = timer)
                        }, edit = { record -> editingId = record.id; editor = record.draft })
                    }
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
                            .clickable { repo.update { it.copy(theme = palette.id) }; themesOpen = false }.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(Modifier.size(16.dp).background(if (palette.id == "signal-blue") palette.card else palette.accent, CircleShape)); Box(Modifier.size(16.dp).background(palette.accent2, CircleShape))
                            }
                            Text(palette.name, color = palette.text, fontSize = 13.sp)
                        }
                    }
                }
            }
            if (clockFontsOpen) ClockFontPicker(theme, clockFont, close = { clockFontsOpen = false }) { font ->
                repo.update { it.copy(clockFontId = font.id.takeUnless { font == ClockFont.SYSTEM }) }
                clockFontsOpen = false
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
                confirmButton = { TextButton(onClick = { repo.report(null) }) { Text("OK") } },
                dismissButton = {
                    if (!controller.scheduler.exactAllowed || !controller.scheduler.notificationsAllowed) {
                        TextButton(onClick = { repo.report(null); permissionsOpen = true }) { Text("Alarm access") }
                    }
                })
        }
    }
}

@Composable private fun ClockScreen(use24: Boolean, theme: LunkTheme, clockFont: ClockFont, alarms: () -> Unit, about: () -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val latest by rememberUpdatedState(alarms)
    val showAbout by rememberUpdatedState(about)
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(500) } }
    BoxWithConstraints(Modifier.fillMaxSize().testTag("big-clock").semantics {
        customActions = listOf(CustomAccessibilityAction("About LunkAlarm") { about(); true })
    }.pointerInput(Unit) {
        var movement = 0f
        detectVerticalDragGestures(onDragStart = { movement = 0f }, onVerticalDrag = { _, dy -> movement += dy },
            onDragEnd = {
                if (movement < -48.dp.toPx()) latest()
                else if (movement > 48.dp.toPx()) showAbout()
            })
    }) {
        IconButton(onClick = about, modifier = Modifier.align(Alignment.TopCenter).testTag("open-about")) {
            Icon(Icons.Default.KeyboardArrowDown, "About LunkAlarm", tint = theme.muted, modifier = Modifier.size(20.dp))
        }
        val date = Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault())
        val display = date.format(DateTimeFormatter.ofPattern(if (use24) "HH:mm" else "h:mm"))
        val size = min(maxWidth.value / (if (display.length > 4) 3.4f else 2.7f), (maxHeight.value - 130) * .5f).coerceIn(48f, 200f)
        val spacing = if (clockFont == ClockFont.SYSTEM) -.035f else 0f
        val style = LocalTextStyle.current.copy(fontFamily = clockFont.family, fontWeight = clockFont.weight,
            fontSize = size.sp, letterSpacing = (size * spacing).sp, fontFeatureSettings = "tnum")
        val measurer = rememberTextMeasurer()
        val detailStyle = LocalTextStyle.current.copy(fontFamily = clockFont.family, fontSize = 22.sp)
        val detailWidth = measurer.measure(if (use24) "00" else "PM", detailStyle).size.width
        val timeWidth = measurer.measure(display, style, softWrap = false).size.width
        val availableWidth = with(LocalDensity.current) { (maxWidth - 46.dp).toPx() } - detailWidth
        val fittedSize = size * (availableWidth / timeWidth.coerceAtLeast(1)).coerceIn(.25f, 1f)
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(display, style = style, fontSize = fittedSize.sp, lineHeight = (fittedSize * 1.05f).sp,
                    color = theme.text, letterSpacing = (fittedSize * spacing).sp, maxLines = 1, softWrap = false)
                Column(Modifier.padding(top = (fittedSize * .12f).dp)) {
                    Text(date.format(DateTimeFormatter.ofPattern("ss")), style = detailStyle, color = theme.accent)
                    if (!use24) Text(date.format(DateTimeFormatter.ofPattern("a")), style = detailStyle, fontSize = 17.sp, color = theme.muted)
                }
            }
            Text(date.format(DateTimeFormatter.ofPattern("EEEE, MMMM d")), color = theme.text, fontSize = 17.sp, modifier = Modifier.padding(top = 14.dp))
            Text(ZoneId.systemDefault().id, color = theme.muted, fontSize = 12.sp, modifier = Modifier.padding(top = 5.dp))
            Column(Modifier.padding(top = 28.dp).clickable(onClick = alarms).padding(12.dp).testTag("view-alarms"), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.KeyboardArrowUp, null, tint = theme.muted, modifier = Modifier.size(20.dp))
                Text("Swipe up to view alarms", color = theme.muted, fontSize = 12.sp)
            }
        }
    }
}

@Composable private fun AboutScreen(theme: LunkTheme, use24Hour: Boolean, clockFont: ClockFont, clock: () -> Unit,
                                    chooseTheme: () -> Unit, chooseFont: () -> Unit, toggleFormat: () -> Unit) {
    val latestClock by rememberUpdatedState(clock)
    val swipeToClock = remember {
        object : NestedScrollConnection {
            private var distance = 0f
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput) {
                    if (available.y < 0) {
                        distance -= available.y
                        if (distance >= 120f) { distance = 0f; latestClock() }
                    } else if (available.y > 0) distance = 0f
                }
                return Offset.Zero
            }
            override suspend fun onPreFling(available: androidx.compose.ui.unit.Velocity): androidx.compose.ui.unit.Velocity {
                distance = 0f
                return androidx.compose.ui.unit.Velocity.Zero
            }
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().testTag("about-page").nestedScroll(swipeToClock).pointerInput(Unit) {
        var distance = 0f
        detectVerticalDragGestures(onDragStart = { distance = 0f }, onVerticalDrag = { _, dy -> distance += dy },
            onDragEnd = { if (distance < -48.dp.toPx()) latestClock() })
    }) {
        val controlsInset = minOf(60.dp, maxHeight * .08f)
        Column(Modifier.align(Alignment.TopCenter).widthIn(max = 480.dp).fillMaxWidth()
            .padding(bottom = 64.dp).verticalScroll(rememberScrollState())
            .heightIn(min = (maxHeight - 64.dp).coerceAtLeast(0.dp)).padding(24.dp),
            verticalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("LunkAlarm", fontSize = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                    Text("By Tristan Josh E. Sibug", color = theme.muted)
                }
                Text("I made this app to wake me from my daily deep slumber", color = theme.accent, fontSize = 22.sp)
            }
            Column(Modifier.padding(bottom = controlsInset),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                AboutControl("Theme", theme, opensPicker = true, click = chooseTheme)
                AboutControl("Clock font", theme, detail = clockFont.title, opensPicker = true, click = chooseFont)
                AboutControl("Clock format", theme, detail = if (use24Hour) "24-hour · 14:30" else "12-hour · 2:30 PM", click = toggleFormat)
            }
        }
        TextButton(onClick = clock, modifier = Modifier.align(Alignment.BottomCenter).padding(12.dp)) {
            Icon(Icons.Default.KeyboardArrowUp, null, tint = theme.muted)
            Text("Clock", color = theme.muted)
        }
    }
}

@Composable private fun AboutControl(label: String, theme: LunkTheme, detail: String? = null,
                                     opensPicker: Boolean = false, click: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(shape)
        .background(theme.text.copy(alpha = .065f)).border(1.dp, theme.border, shape)
        .clickable(role = Role.Button, onClick = click).padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = theme.text, fontWeight = FontWeight.SemiBold)
        detail?.let { Text(it, color = theme.muted) }
        if (opensPicker) Icon(Icons.Default.ChevronRight, null, Modifier.size(18.dp), tint = theme.muted)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ClockFontPicker(theme: LunkTheme, selected: ClockFont, close: () -> Unit,
                                       choose: (ClockFont) -> Unit) {
    ModalBottomSheet(onDismissRequest = close, containerColor = theme.card) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Clock font", Modifier.semantics { heading() }, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            ClockFont.entries.forEach { font ->
                val shape = RoundedCornerShape(16.dp)
                val isSelected = selected == font
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(shape).background(theme.field)
                    .border(1.dp, if (isSelected) theme.accent else theme.border, shape)
                    .selectable(isSelected, role = Role.RadioButton) { choose(font) }.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("12:38", Modifier.clearAndSetSemantics {}, fontSize = 32.sp,
                        fontFamily = font.family, fontWeight = font.weight, color = theme.text)
                    Spacer(Modifier.weight(1f))
                    Text(font.title, color = theme.text)
                    if (isSelected) Icon(Icons.Default.CheckCircle, null, tint = theme.accent)
                }
            }
        }
    }
}

@Composable private fun SavedAlarmScreen(state: AppState, theme: LunkTheme, controller: AlarmController, clock: () -> Unit, add: (Boolean) -> Unit, edit: (AlarmRecord) -> Unit) {
    val list = rememberLazyListState()
    var smartDuplicateId by rememberSaveable { mutableStateOf<String?>(null) }
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
                    if (state.alarms.isEmpty()) {
                        Text("Alarms & timers", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = theme.text, modifier = Modifier.testTag("alarms-heading"))
                        Text("No upcoming alarms", fontSize = 14.sp, color = theme.muted)
                    }
                }
            }
            if (state.alarms.isEmpty()) item { Text("No alarms yet. Tap + to add one.", color = theme.muted, modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp)) }
            listOf(true, false).forEach { timer ->
                val records = state.alarms.filter { it.draft.timer == timer }.sortedBy { it.target }
                if (records.isNotEmpty()) {
                    item(key = if (timer) "timers-heading" else "alarms-heading") {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(if (timer) "Timers" else "Alarms", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = theme.text,
                                modifier = Modifier.testTag(if (timer) "timers-heading" else "alarms-heading"))
                            val next = records.filter { it.enabled && it.error == null }.minByOrNull { it.target }
                            Text(next?.let { (if (timer) "Next timer " else "Next alarm ") + Instant.ofEpochMilli(it.target).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(if (state.use24Hour) "MMM d, HH:mm" else "MMM d, h:mm a")) }
                                ?: (if (timer) "No upcoming timers" else "No upcoming alarms"), color = theme.muted, fontSize = 14.sp)
                        }
                    }
                    items(records, key = { it.id }) { record ->
                        AlarmCardRow(record, state.use24Hour, theme, controller, edit, smartDuplicate = { smartDuplicateId = record.id })
                    }
                }
            }
        }
        var addOpen by remember { mutableStateOf(false) }
        Box(Modifier.align(Alignment.BottomEnd).padding(24.dp)) {
            FloatingActionButton(onClick = { addOpen = !addOpen }, modifier = Modifier.testTag("new-alarm"),
                shape = CircleShape, containerColor = theme.accent2, contentColor = theme.onAccent) {
                Icon(if (addOpen) Icons.Default.Close else Icons.Default.Add, "Add alarm or timer", Modifier.size(30.dp))
            }
            DropdownMenu(expanded = addOpen, onDismissRequest = { addOpen = false }, containerColor = theme.card) {
                DropdownMenuItem(text = { Text("Alarm", color = theme.text) }, leadingIcon = { Icon(Icons.Default.Alarm, null, tint = theme.accent2) },
                    onClick = { addOpen = false; add(false) }, modifier = Modifier.testTag("add-menu-alarm"))
                DropdownMenuItem(text = { Text("Timer", color = theme.text) }, leadingIcon = { Icon(Icons.Default.Timer, null, tint = theme.accent) },
                    onClick = { addOpen = false; add(true) }, modifier = Modifier.testTag("add-menu-timer"))
            }
        }
    }
    val source = state.alarms.firstOrNull { it.id == smartDuplicateId && !it.active }
    if (source != null) key(source.id) {
        SmartDuplicateDialog(source, theme, close = { smartDuplicateId = null }) { count, minutes, copyTests ->
            if (controller.smartDuplicate(source.id, count, minutes, copyTests)) smartDuplicateId = null
        }
    }
}

@Composable private fun AlarmCardRow(alarm: AlarmRecord, use24: Boolean, palette: LunkTheme, controller: AlarmController,
                                    edit: (AlarmRecord) -> Unit, smartDuplicate: () -> Unit) {
    val theme = palette.cardPalette
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
        }.semantics {
            customActions = if (alarm.active) emptyList() else buildList {
                add(CustomAccessibilityAction("Delete") { controller.remove(alarm) })
                add(CustomAccessibilityAction("Duplicate") { controller.duplicate(alarm) })
                if (!alarm.draft.timer) add(CustomAccessibilityAction("Smart Duplicate") { smartDuplicate(); true })
            }
        }) {
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
                    if (alarm.draft.timer || alarm.hasTests) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (alarm.draft.timer) Text("Countdown", color = theme.muted, fontSize = 11.sp)
                            WakeTest.entries.filter { it.enabled(alarm.draft) }.forEach { test ->
                                TestGlyph(test, theme.muted, Modifier.size(14.dp).clearAndSetSemantics { contentDescription = test.short },
                                    textSize = 11.sp)
                            }
                        }
                    }
                }
                if (!alarm.draft.timer) Switch(checked = alarm.enabled, onCheckedChange = { controller.enable(alarm, it) }, enabled = !alarm.active,
                    colors = SwitchDefaults.colors(checkedTrackColor = theme.accent2, checkedThumbColor = androidx.compose.ui.graphics.Color.White), modifier = Modifier.testTag("enabled-${alarm.id}"))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (alarm.draft.timer) Text("Rings at " + Instant.ofEpochMilli(alarm.target).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(if (use24) "HH:mm" else "h:mm a")), color = theme.muted, fontSize = 11.sp, modifier = Modifier.weight(1f))
                else if (alarm.draft.days.size == 7) Text("Daily", color = theme.muted, fontSize = 11.sp, modifier = Modifier.weight(1f).testTag("daily-${alarm.id}"))
                else Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    (1..7).forEach { day ->
                        val selected = day in alarm.draft.days
                        Box(Modifier.size(26.dp).then(if (selected) Modifier.background(theme.dayAccent.copy(alpha = .1f), CircleShape)
                            .border(1.dp, theme.dayAccent.copy(alpha = .65f), CircleShape) else Modifier)
                            .clearAndSetSemantics { contentDescription = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")[day - 1] + if (selected) ", selected" else ", not selected" }, contentAlignment = Alignment.Center) {
                            Text(listOf("S", "M", "T", "W", "T", "F", "S")[day - 1], fontSize = 11.sp, color = if (selected) theme.dayAccent else theme.muted)
                        }
                    }
                }
                Box {
                    IconButton(onClick = { menu = true }, enabled = !alarm.active, modifier = Modifier.size(40.dp, 32.dp).testTag("options-${alarm.id}")) { Icon(Icons.Default.MoreVert, "Options for ${alarm.label}", tint = theme.text) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; controller.remove(alarm) })
                        DropdownMenuItem(text = { Text("Duplicate") }, onClick = { menu = false; controller.duplicate(alarm) })
                        if (!alarm.draft.timer) {
                            DropdownMenuItem(text = { Text("Smart Duplicate") }, onClick = { menu = false; smartDuplicate() })
                        }
                    }
                }
            }
            alarm.error?.let { Text(it, fontSize = 12.sp, color = theme.accent) }
            if (alarm.active) TextButton(onClick = { view.context.startActivity(RingingActivity.intent(view.context)) }) { Text("Finish wake-up tests") }
        }
    }
}

@Composable private fun SmartDuplicateDialog(alarm: AlarmRecord, theme: LunkTheme, close: () -> Unit,
                                             create: (Int, Int, Boolean) -> Unit) {
    var count by rememberSaveable { mutableIntStateOf(1) }
    var useHours by rememberSaveable { mutableStateOf(false) }
    var minutes by rememberSaveable { mutableStateOf("5") }
    var hours by rememberSaveable { mutableStateOf("1") }
    var copyTests by rememberSaveable { mutableStateOf(false) }
    var showTestsHelp by rememberSaveable { mutableStateOf(false) }
    val intervalText = if (useHours) hours else minutes
    val range = if (useHours) AlarmRecord.smartDuplicateHourIntervals else AlarmRecord.smartDuplicateMinuteIntervals
    val interval = intervalText.toIntOrNull()?.takeIf { it in range }
    val stepValue = (intervalText.toIntOrNull() ?: range.first).coerceIn(range)
    fun setInterval(text: String) {
        val digits = text.filter { it in '0'..'9' }
        if (useHours) hours = digits else minutes = digits
    }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("Smart Duplicate") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                DuplicateStepper("Duplicates", count, AlarmRecord.smartDuplicateCounts) { count = it }
                Text("Time between alarms")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !useHours, onClick = { useHours = false }, label = { Text("Minutes") })
                    FilterChip(selected = useHours, onClick = { useHours = true }, label = { Text("Hours") })
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(value = intervalText, onValueChange = ::setInterval,
                        modifier = Modifier.weight(1f).testTag("smart-duplicate-interval"),
                        label = { Text(if (useHours) "Hours apart" else "Minutes apart") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
                    IconButton(onClick = { setInterval((stepValue - 1).toString()) }, enabled = stepValue > range.first) {
                        Icon(Icons.Default.Remove, "Decrease interval")
                    }
                    IconButton(onClick = { setInterval((stepValue + 1).toString()) }, enabled = stepValue < range.last) {
                        Icon(Icons.Default.Add, "Increase interval")
                    }
                }
                Text(if (useHours) "1–23 hours" else "1–59 minutes", fontSize = 12.sp, color = theme.muted)
                if (alarm.hasTests) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Which alarms should use the wake-up tests?", Modifier.weight(1f))
                        IconButton(onClick = { showTestsHelp = !showTestsHelp }) {
                            Icon(Icons.AutoMirrored.Filled.HelpOutline, "How wake-up tests queue", tint = theme.accent)
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = !copyTests, onClick = { copyTests = false }, label = { Text("Original only") })
                        FilterChip(selected = copyTests, onClick = { copyTests = true }, label = { Text("All alarms") })
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { interval?.let { create(count, if (useHours) it * 60 else it, copyTests) } },
                enabled = interval != null, modifier = Modifier.testTag("create-smart-duplicates")) {
                Text(if (count == 1) "Create 1 duplicate" else "Create $count duplicates", color = theme.accent)
            }
        },
        dismissButton = { TextButton(onClick = close) { Text("Cancel") } },
        containerColor = theme.card
    )
    if (showTestsHelp) AlertDialog(
        onDismissRequest = { showTestsHelp = false },
        title = { Text("Queued wake-up tests") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Wake-up tests queue up as alarms ring.")
                Text("Finish the current set to start the next one.")
                Text(buildAnnotatedString {
                    append("Choose ")
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("Original only") }
                    append(" to keep wake-up tests on the first alarm.")
                })
            }
        },
        confirmButton = { TextButton(onClick = { showTestsHelp = false }) { Text("OK") } },
        containerColor = theme.card
    )
}

@Composable private fun DuplicateStepper(label: String, value: Int, range: IntRange, change: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        IconButton(onClick = { change(value - 1) }, enabled = value > range.first) {
            Icon(Icons.Default.Remove, "Decrease $label")
        }
        Text(value.toString())
        IconButton(onClick = { change(value + 1) }, enabled = value < range.last) {
            Icon(Icons.Default.Add, "Increase $label")
        }
    }
}
