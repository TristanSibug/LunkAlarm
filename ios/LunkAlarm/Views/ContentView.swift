import SwiftUI

struct ContentView: View {
    @Bindable var store: AlarmStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickerOpen = false
    @State private var themeOpen = false
    @State private var editor: AlarmEditorPresentation?
    @State private var ringingOpen = false
    @State private var clockControls: UUID? = UUID()
    @Namespace private var clockSpace

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AlarmBackground(theme: store.theme)
                ZStack {
                    if pickerOpen {
                        SavedAlarmsView(store: store, returnToClock: { pickerOpen = false }, add: { mode in
                            store.state.settings.alarmName = ""; store.state.settings.mode = mode
                            editor = AlarmEditorPresentation(editingID: nil, mode: mode)
                        }, edit: { alarm in
                            store.loadEditor(alarm)
                            editor = AlarmEditorPresentation(editingID: alarm.id, mode: alarm.isTimer ? .timer : .time)
                        })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack {
                            Spacer(minLength: 8)
                            clock(width: geometry.size.width, height: geometry.size.height * 0.66)
                            Spacer(minLength: 8)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .contentShape(Rectangle())
                            .gesture(AlarmNavigationSwipe(direction: .up, action: showAlarms))
                            .gesture(AlarmNavigationSwipe(direction: .down, action: revealClockControls))
                            .accessibilityAction(named: "View alarms") { showAlarms() }
                            .accessibilityAction(named: "Show clock controls") { revealClockControls() }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }.overlay(alignment: .topTrailing) {
                if !pickerOpen && clockControls != nil {
                    toolbar.padding(.trailing, 20).padding(.top, 12)
                        .transition(.opacity)
                }
            }.foregroundStyle(store.theme.text)
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.88), value: pickerOpen)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: clockControls != nil)
        }
        .task(id: clockControls) {
            guard clockControls != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            clockControls = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clockControls = nil }
        }
        .sheet(isPresented: $themeOpen) { themeSheet }
        .sheet(item: $editor) { presentation in
            SheetShell(title: presentation.title, theme: store.theme, scrolls: false, showsDone: false) {
                AlarmEditorView(store: store, editingID: presentation.editingID, onAdded: { editor = nil })
            }
        }
        .onChange(of: store.ringing?.id, initial: true) { _, id in
            guard let id else { ringingOpen = false; return }
            editor = nil; themeOpen = false; clockControls = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if store.ringing?.id == id { ringingOpen = true }
            }
        }
        .fullScreenCover(isPresented: $ringingOpen) {
            RingingView(store: store).interactiveDismissDisabled()
                .preferredColorScheme(store.theme.isLight ? .light : .dark)
        }
        .alert("LunkAlarm", isPresented: Binding(get: { store.errorMessage != nil && store.ringing == nil }, set: { if !$0 { store.errorMessage = nil } })) {
            if store.alarmAccessDenied {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func showAlarms() {
        clockControls = nil
        pickerOpen = true
    }

    private func revealClockControls() {
        guard !pickerOpen else { return }
        clockControls = UUID()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Theme") { themeOpen = true }.buttonStyle(ChipStyle(theme: store.theme))
            Button(store.state.settings.use24Hour ? "24h" : "12h") { store.state.settings.use24Hour.toggle() }
                .buttonStyle(ChipStyle(theme: store.theme)).accessibilityLabel("Switch clock format")
        }
    }
    private func clock(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 24) {
            ClockFaceView(use24Hour: store.state.settings.use24Hour, theme: store.theme,
                          digitSize: min(pickerOpen ? 146 : 260, max(64, min((width - 55) * 0.36, height * 0.46))))
                .matchedGeometryEffect(id: "clock", in: clockSpace)
            HStack(spacing: 10) {
                VStack(spacing: 7) {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                    Text("Swipe up to view alarms").font(.system(size: 12))
                }.foregroundStyle(store.theme.muted).padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Swipe up to view alarms")
                    .accessibilityAction { showAlarms() }
                    .accessibilityIdentifier("alarmSwipeHint")
            }
        }.padding(.vertical, pickerOpen ? 18 : 10).frame(maxWidth: .infinity)
    }
    private var themeSheet: some View {
        SheetShell(title: "Theme", theme: store.theme) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AlarmTheme.arranged) { theme in
                    Button { store.state.settings.themeID = theme.id; themeOpen = false } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Circle().fill(theme.id == "signal-blue" ? theme.card : theme.accent).frame(width: 16, height: 16)
                                Circle().fill(theme.accent2).frame(width: 16, height: 16)
                                Spacer()
                                if store.state.settings.themeID == theme.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                            }
                            Text(theme.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                        }.padding(16).background(theme.background, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(store.state.settings.themeID == theme.id ? theme.accent : theme.border))
                    }.buttonStyle(.plain).accessibilityLabel(theme.name).accessibilityAddTraits(store.state.settings.themeID == theme.id ? .isSelected : [])
                }
            }
        }
    }
}

// Sheet identity and edit target travel together, including the first sheet
// presented after launch. A separate Boolean can present stale/nil edit state.
private struct AlarmEditorPresentation: Identifiable {
    let id = UUID()
    let editingID: UUID?
    let mode: AlarmMode
    var title: String { (editingID == nil ? "New " : "Edit ") + (mode == .timer ? "timer" : "alarm") }
}

struct ClockFaceView: View {
    let use24Hour: Bool
    let theme: AlarmTheme
    let digitSize: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
            let hour = parts.hour ?? 0
            let time = String(format: use24Hour ? "%02d:%02d" : "%d:%02d", use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12), parts.minute ?? 0)
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 7) {
                    Text(time).font(.system(size: digitSize, weight: .ultraLight)).tracking(-digitSize * 0.035)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(theme.text)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%02d", parts.second ?? 0)).foregroundStyle(theme.gradient)
                        if !use24Hour { Text(hour < 12 ? "AM" : "PM").font(.system(size: 17)).foregroundStyle(theme.muted) }
                    }.font(.system(size: 22, weight: .regular)).monospacedDigit().padding(.top, 9)
                }.accessibilityElement(children: .ignore).accessibilityLabel(context.date.formatted(date: .omitted, time: .standard))
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day()).font(.system(size: 17, weight: .medium)).padding(.top, 10)
                Text(TimeZone.current.identifier).font(.system(size: 12)).foregroundStyle(theme.muted)
            }.frame(maxWidth: .infinity)
        }
    }
}

struct SheetShell<Content: View>: View {
    let title: String
    let theme: AlarmTheme
    var scrolls = true
    var showsDone = true
    var closeLabel = "Close alarm editor"
    var closeDisabled = false
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if scrolls { ScrollView { content.padding(20) }.scrollDismissesKeyboard(.interactively) }
                else { content }
            }
                .background(theme.background).foregroundStyle(theme.text)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if showsDone { Button("Done") { dismiss() } }
                        else {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(closeLabel).accessibilityIdentifier("closeAlarmEditor")
                                .disabled(closeDisabled)
                        }
                    }
                }
                .toolbarBackground(theme.card, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.tint(theme.accent).preferredColorScheme(theme.isLight ? .light : .dark)
            .presentationDragIndicator(.visible).presentationBackground(theme.background)
    }
}
