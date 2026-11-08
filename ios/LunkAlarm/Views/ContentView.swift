import SwiftUI

struct ContentView: View {
    @Bindable var store: AlarmStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var pickerOpen = false
    @State private var themeOpen = false
    @State private var alarmsOpen = false
    @Namespace private var clockSpace

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AlarmBackground(theme: store.theme)
                VStack(spacing: 0) {
                    toolbar.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    if pickerOpen {
                        ScrollView {
                            VStack(spacing: 20) {
                                clock(width: geometry.size.width, height: 270)
                                AlarmEditorView(store: store)
                                alarmList
                                Text("Alarms and themes are saved on this iPhone.")
                                    .font(.caption2).foregroundStyle(store.theme.muted).padding(.bottom, 16)
                            }.padding(.horizontal, 16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                        }.scrollDismissesKeyboard(.interactively)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                    }
                }
            }.foregroundStyle(store.theme.text)
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.88), value: pickerOpen)
        }
        .sheet(isPresented: $themeOpen) { themeSheet }
        .sheet(isPresented: $alarmsOpen) {
            SheetShell(title: "Your alarms", theme: store.theme) { alarmList }
        }
        .fullScreenCover(isPresented: Binding(get: { store.ringing != nil }, set: { _ in })) {
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
            HStack(spacing: 10) {
                Button {
                    pickerOpen.toggle()
                } label: {
                    Label(pickerOpen ? "Hide alarm picker" : "Add alarm", systemImage: pickerOpen ? "minus" : "plus")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 12)
                        .foregroundStyle(pickerOpen ? store.theme.text : store.theme.onAccent)
                        .background {
                            if pickerOpen { Capsule().fill(store.theme.card) }
                            else { Capsule().fill(store.theme.gradient) }
                        }.overlay(Capsule().stroke(store.theme.border))
                }.buttonStyle(.plain).accessibilityIdentifier("alarmPickerToggle")
                if !pickerOpen && !store.state.alarms.isEmpty {
                    Button("Your alarms (\(store.state.alarms.count))") { alarmsOpen = true }.buttonStyle(ChipStyle(theme: store.theme))
                }
            }
        }.padding(.vertical, pickerOpen ? 18 : 10).frame(maxWidth: .infinity)
    }
    private var alarmList: some View {
        AlarmCard(theme: store.theme) {
            HStack {
                Text("Your alarms").font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(store.state.alarms.count)").font(.caption)
            }.foregroundStyle(store.theme.muted)
            if store.state.alarms.isEmpty {
                Text("No alarms yet. Add one above.").font(.system(size: 13)).foregroundStyle(store.theme.muted)
            }
            ForEach(store.orderedAlarms) { alarm in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alarm.target.formatted(.dateTime.hour().minute().locale(Locale(identifier: store.state.settings.use24Hour ? "en_GB" : "en_US"))))
                            .font(.system(size: 28, weight: .light)).monospacedDigit()
                        Text(alarm.target.formatted(date: .abbreviated, time: .omitted) + " · " + alarm.soundName)
                            .font(.caption).foregroundStyle(store.theme.muted)
                        if alarm.status == .notScheduled {
                            Text("Not scheduled by iOS. Remove and add again.").font(.caption).foregroundStyle(.orange)
                        }
                        if alarm.hasTests {
                            Text([alarm.typing ? "Typing test" : nil, alarm.mathCount > 0 ? "\(alarm.mathCount) math problems" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(store.theme.muted)
                        }
                        if alarm.status == .needsChallenge {
                            Button("Finish wake-up tests") { alarmsOpen = false; store.begin(alarm) }
                                .font(.caption.weight(.semibold)).foregroundStyle(store.theme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) { store.remove(alarm) } label: { Image(systemName: "trash").padding(10) }
                        .accessibilityLabel("Delete alarm at \(alarm.target.formatted(date: .omitted, time: .shortened))")
                        .disabled(store.readOnly || store.saving)
                }.padding(.vertical, 8)
                if alarm.id != store.orderedAlarms.last?.id { Divider().overlay(store.theme.border) }
            }
        }
    }
    private var themeSheet: some View {
        SheetShell(title: "Theme", theme: store.theme) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AlarmTheme.all) { theme in
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
            ScrollView { content.padding(20) }
                .background(theme.background).foregroundStyle(theme.text)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .toolbarBackground(theme.card, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.tint(theme.accent).preferredColorScheme(theme.isLight ? .light : .dark)
            .presentationDragIndicator(.visible).presentationBackground(theme.background)
    }
}
