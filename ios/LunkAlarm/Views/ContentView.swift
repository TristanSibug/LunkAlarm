import SwiftUI

struct ContentView: View {
    @Bindable var store: AlarmStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: HomePage = .clock
    @State private var themeOpen = false
    @State private var fontPickerOpen = false
    @State private var editor: AlarmEditorPresentation?
    @State private var ringingOpen = false
    @State private var appIcon = ThemeAppIcon()
    private enum HomePage: Equatable { case about, clock, alarms }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AlarmBackground(theme: store.theme)
                ZStack {
                    switch page {
                    case .alarms:
                        SavedAlarmsView(store: store, returnToClock: { page = .clock }, add: { mode in
                            store.state.settings.alarmName = ""; store.state.settings.mode = mode
                            editor = AlarmEditorPresentation(editingID: nil, mode: mode)
                        }, edit: { alarm in
                            store.loadEditor(alarm)
                            editor = AlarmEditorPresentation(editingID: alarm.id, mode: alarm.isTimer ? .timer : .time)
                        })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .about:
                        aboutPage.transition(.move(edge: .top).combined(with: .opacity))
                    case .clock:
                        VStack {
                            Spacer(minLength: 8)
                            clock(width: geometry.size.width, height: geometry.size.height * 0.66)
                            Spacer(minLength: 8)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                Button { page = .about } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(store.theme.muted)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("About LunkAlarm")
                                    .accessibilityIdentifier("openAbout")
                            }
                            .transition(.opacity)
                            .contentShape(Rectangle())
                            .gesture(AlarmNavigationSwipe(direction: .up) { page = .alarms })
                            .gesture(AlarmNavigationSwipe(direction: .down) { page = .about })
                            .accessibilityAction(named: "View alarms") { page = .alarms }
                            .accessibilityAction(named: "About LunkAlarm") { page = .about }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }.foregroundStyle(store.theme.text)
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.88), value: page)
        }
        .sheet(isPresented: $themeOpen, onDismiss: syncAppIcon) { themeSheet }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { syncAppIcon() }
        }
        .sheet(isPresented: $fontPickerOpen) { clockFontSheet }
        .sheet(item: $editor) { presentation in
            SheetShell(title: presentation.title, theme: store.theme, scrolls: false, showsDone: false) {
                AlarmEditorView(store: store, editingID: presentation.editingID, onAdded: { editor = nil })
            }
        }
        .onChange(of: store.ringing?.id, initial: true) { _, id in
            guard let id else { ringingOpen = false; return }
            editor = nil; themeOpen = false; fontPickerOpen = false
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

    private func syncAppIcon() {
        guard !themeOpen, store.ringing == nil else { return }
        appIcon.sync(with: store.theme.id)
    }

    private var aboutPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LunkAlarm").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("By Tristan Josh E. Sibug").foregroundStyle(store.theme.muted)
                    }
                    Text("I made this app to wake me from my daily deep slumber")
                        .font(.title2).foregroundStyle(store.theme.accent)
                    Spacer(minLength: 0)
                    aboutControls.padding(.bottom, min(60, geometry.size.height * 0.08))
                }
                .frame(minHeight: max(0, geometry.size.height - 48), alignment: .top)
                .frame(maxWidth: 480, alignment: .leading).padding(24)
                .frame(maxWidth: .infinity)
            }
        }.safeAreaInset(edge: .bottom) {
            Button { page = .clock } label: { Label("Clock", systemImage: "chevron.up") }
                .buttonStyle(.plain).foregroundStyle(store.theme.muted).padding(16)
        }.gesture(AlarmNavigationSwipe(direction: .up) { page = .clock })
            .accessibilityIdentifier("aboutPage")
    }

    private var aboutControls: some View {
        let use24Hour = store.state.settings.use24Hour
        let format = use24Hour ? "24-hour" : "12-hour"
        let example = use24Hour ? "14:30" : "2:30 PM"
        return VStack(spacing: 12) {
            Button { themeOpen = true } label: {
                HStack {
                    Text("Theme")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote)
                        .foregroundStyle(store.theme.muted).accessibilityHidden(true)
                }
            }.accessibilityLabel("Theme")
            Button { fontPickerOpen = true } label: {
                HStack {
                    Text("Clock font")
                    Spacer()
                    Text(clockFont.name).foregroundStyle(store.theme.muted)
                    Image(systemName: "chevron.right").font(.footnote)
                        .foregroundStyle(store.theme.muted).accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Clock font")
            .accessibilityValue(clockFont.name)
            Button { store.state.settings.use24Hour.toggle() } label: {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Clock format")
                        Spacer()
                        Text("\(format) · \(example)").foregroundStyle(store.theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clock format")
                        Text("\(format) · \(example)").foregroundStyle(store.theme.muted)
                    }
                }
            }
            .accessibilityLabel("Switch clock format")
            .accessibilityValue("\(format), for example \(example)")
        }
        .buttonStyle(AboutControlStyle(theme: store.theme))
    }

    private var clockFont: ClockFont {
        store.state.settings.clockFontID.flatMap(ClockFont.init(rawValue:)) ?? .system
    }

    private func clock(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 24) {
            ClockFaceView(use24Hour: store.state.settings.use24Hour, theme: store.theme, clockFont: clockFont,
                          digitSize: min(260, max(64, min((width - 55) * 0.36, height * 0.46))))
            HStack(spacing: 10) {
                VStack(spacing: 7) {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                    Text("Swipe up to view alarms").font(.system(size: 12))
                }.foregroundStyle(store.theme.muted).padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Swipe up to view alarms")
                    .accessibilityAction { page = .alarms }
                    .accessibilityIdentifier("alarmSwipeHint")
            }
        }.padding(.vertical, 10).frame(maxWidth: .infinity)
    }

    private var clockFontSheet: some View {
        SheetShell(title: "Clock font", theme: store.theme) {
            VStack(spacing: 12) {
                ForEach(ClockFont.allCases, id: \.self) { font in
                    Button {
                        store.state.settings.clockFontID = font == .system ? nil : font.rawValue
                        fontPickerOpen = false
                    } label: {
                        HStack(spacing: 12) {
                            Text("12:38").font(font.timeFont(size: 36)).monospacedDigit()
                                .accessibilityHidden(true)
                            Spacer()
                            Text(font.name)
                            if clockFont == font {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(store.theme.accent)
                                    .accessibilityHidden(true)
                            }
                        }.padding(.vertical, 8)
                    }
                    .accessibilityLabel(font.name)
                    .accessibilityAddTraits(clockFont == font ? .isSelected : [])
                }
            }.buttonStyle(AboutControlStyle(theme: store.theme))
        }
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

private struct AboutControlStyle: ButtonStyle {
    let theme: AlarmTheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 16)
            .background(theme.text.opacity(configuration.isPressed ? 0.15 : 0.065), in: shape)
            .overlay(shape.strokeBorder(theme.border))
            .contentShape(shape)
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

private enum ClockFont: String, CaseIterable {
    case system, rounded, serif, monospaced

    var name: String {
        switch self {
        case .system: "System Light"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        }
    }

    private var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    func timeFont(size: CGFloat) -> Font {
        let weight: Font.Weight = switch self {
        case .system: .ultraLight
        case .rounded, .monospaced: .light
        case .serif: .regular
        }
        return .system(size: size, weight: weight, design: design)
    }

    func detailFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: design)
    }
}

private struct ClockFaceView: View {
    let use24Hour: Bool
    let theme: AlarmTheme
    let clockFont: ClockFont
    let digitSize: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
            let hour = parts.hour ?? 0
            let time = String(format: use24Hour ? "%02d:%02d" : "%d:%02d", use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12), parts.minute ?? 0)
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 7) {
                    Text(time).font(clockFont.timeFont(size: digitSize))
                        .tracking(clockFont == .system ? -digitSize * 0.035 : 0)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(theme.text)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%02d", parts.second ?? 0)).foregroundStyle(theme.gradient)
                        if !use24Hour { Text(hour < 12 ? "AM" : "PM").font(clockFont.detailFont(size: 17)).foregroundStyle(theme.muted) }
                    }.font(clockFont.detailFont(size: 22)).monospacedDigit().padding(.top, 9)
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
