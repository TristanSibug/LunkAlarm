import SwiftUI

struct ContentView: View {
    @Bindable var store: AlarmStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var pickerOpen = false
    @State private var themeOpen = false
    @State private var editorOpen = false
    @State private var ringingOpen = false
    @State private var editingID: UUID?
    @State private var timersOpen = false
    @Namespace private var clockSpace

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AlarmBackground(theme: store.theme)
                VStack(spacing: 0) {
                    toolbar.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    if pickerOpen {
                        SavedAlarmsView(store: store, returnToClock: { pickerOpen = false }, add: {
                            editingID = nil; store.state.settings.alarmName = ""; store.state.settings.mode = .time; editorOpen = true
                        }, edit: { alarm in
                            store.loadEditor(alarm); editingID = alarm.id; editorOpen = true
                        })
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        VStack {
                            Spacer(minLength: 8)
                            clock(width: geometry.size.width, height: geometry.size.height * 0.66)
                            Spacer(minLength: 8)
                            if geometry.size.height > 400 {
                                Text("Scheduled by iOS. No need to keep this screen open.")
                                    .font(.caption2).foregroundStyle(store.theme.muted).multilineTextAlignment(.center)
                                    .padding(.horizontal, 24).padding(.bottom, 16)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(AlarmNavigationSwipe(direction: .up) { pickerOpen = true })
                            .accessibilityAction(named: "View alarms") { pickerOpen = true }
                    }
                }
            }.foregroundStyle(store.theme.text)
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.88), value: pickerOpen)
        }
        .sheet(isPresented: $themeOpen) { themeSheet }
        .sheet(isPresented: $timersOpen) {
            SheetShell(title: "Active timers", theme: store.theme) {
                ForEach(store.orderedAlarms.filter { $0.isTimer }) { alarm in
                    HStack {
                        Text(alarm.target, style: .timer).monospacedDigit()
                        Spacer()
                        Button("Cancel", role: .destructive) { store.remove(alarm) }
                    }.padding(.vertical, 12)
                }
            }
        }
        .sheet(isPresented: $editorOpen) {
            SheetShell(title: editingID == nil ? "New alarm" : "Edit alarm", theme: store.theme) {
                AlarmEditorView(store: store, editingID: editingID, onAdded: { editorOpen = false })
            }
        }
        .onChange(of: store.ringing?.id, initial: true) { _, id in
            guard let id else { ringingOpen = false; return }
            editorOpen = false; timersOpen = false; themeOpen = false
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
            if store.authorizationLabel == "Alarms disabled" {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(store.authorizationLabel == "Alarms disabled" ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(store.authorizationLabel).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
            }.foregroundStyle(store.theme.muted).padding(.horizontal, 10).padding(.vertical, 8)
                .background(store.theme.text.opacity(0.055), in: Capsule())
            Spacer(minLength: 4)
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
            if store.state.alarms.contains(where: { $0.isTimer }) {
                Button("Active timers") { timersOpen = true }.buttonStyle(ChipStyle(theme: store.theme))
            }
            HStack(spacing: 10) {
                VStack(spacing: 7) {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                    Text("Swipe up to view alarms").font(.system(size: 12))
                }.foregroundStyle(store.theme.muted).padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Swipe up to view alarms")
                    .accessibilityAction { pickerOpen = true }
                    .accessibilityIdentifier("alarmSwipeHint")
            }
        }.padding(.vertical, pickerOpen ? 18 : 10).frame(maxWidth: .infinity)
    }
    private var themeSheet: some View {
        SheetShell(title: "Theme", theme: store.theme) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AlarmTheme.arranged) { theme in
                    Button { store.state.settings.themeID = theme.id } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Circle().fill(theme.accent).frame(width: 16, height: 16)
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
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { content.padding(20) }.scrollDismissesKeyboard(.interactively)
                .background(theme.background).foregroundStyle(theme.text)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .toolbarBackground(theme.card, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.tint(theme.accent).preferredColorScheme(theme.isLight ? .light : .dark)
            .presentationDragIndicator(.visible).presentationBackground(theme.background)
    }
}
