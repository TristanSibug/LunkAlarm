import SwiftUI
import UniformTypeIdentifiers

struct AlarmEditorView: View {
    @Bindable var store: AlarmStore
    var editingID: UUID? = nil
    var onAdded: (() -> Void)? = nil
    @State private var ringtoneOpen = false
    @State private var onlineOpen = false
    @State private var importing = false
    @State private var soundCheckOpen = false
    @State private var testsExpanded = true
    @State private var ringtoneAction: RingtoneAction?
    private enum RingtoneAction { case file, online }
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        AlarmCard(theme: store.theme) {
            if onAdded == nil { Text("New alarm").font(.system(size: 14, weight: .medium)).foregroundStyle(store.theme.muted) }
            if store.state.settings.mode == .time {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Alarm name")
                    TextField("Alarm name (optional)", text: Binding(get: { store.state.settings.alarmName ?? "" }, set: { store.state.settings.alarmName = $0 }))
                        .padding(12).background(store.theme.field, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("alarmNameField")
                }
            }
            HStack(spacing: 4) {
                modeButton("At a time", mode: .time)
                modeButton("In how long", mode: .timer)
            }.padding(4).background(store.theme.field, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(store.state.settings.mode == .time ? "Ring at" : "Ring in")
                if store.state.settings.mode == .time { timeWheels } else { durationWheels }
            }
            if store.state.settings.mode == .time { repeatControls }
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Ringtone")
                HStack(spacing: 10) {
                    Button { ringtoneOpen = true } label: {
                        HStack(spacing: 8) {
                            Text(store.selectedSound?.name ?? "Choose a sound").lineLimit(1)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.down").font(.caption)
                        }.font(.system(size: 13)).padding(12).foregroundStyle(store.theme.text)
                            .background(store.theme.field, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(store.theme.border))
                    }.buttonStyle(.plain)
                    Button(store.sound.previewing ? "Stop" : "Preview") { store.preview() }
                        .buttonStyle(ChipStyle(theme: store.theme))
                }
            }.font(.system(size: 13)).foregroundStyle(store.theme.accent)
            soundLevelControls()
            wakeUpTests
            if let message = store.message { Text(message).font(.caption).foregroundStyle(store.theme.accent) }
        }.padding(20)
        }.scrollDismissesKeyboard(.interactively).clipped()
            saveButton.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                .background {
                    LinearGradient(colors: [store.theme.background.opacity(0), store.theme.background.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        .sheet(isPresented: $ringtoneOpen, onDismiss: {
            switch ringtoneAction {
            case .file: importing = true
            case .online: onlineOpen = true
            case nil: break
            }
            ringtoneAction = nil
        }) { ringtoneSheet }
        .sheet(isPresented: $onlineOpen) { onlineSheet }
        .sheet(isPresented: $soundCheckOpen, onDismiss: {
            if store.sound.previewing { store.sound.stop() }
        }) { soundCheckSheet }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): store.importSound(url)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: store.state.settings.ringtoneID) { _, _ in if store.sound.previewing { store.sound.stop() } }
        .onChange(of: store.state.settings.soundLevel) { _, level in store.sound.updatePreviewVolume(level ?? 1) }
    }

    private var saveButton: some View {
        Button {
            Task { if await store.addAlarm(replacing: editingID) { onAdded?() } }
        } label: {
            HStack {
                if store.saving { ProgressView() }
                Text(store.saving ? "Saving…" : editingID == nil ? "Add alarm" : "Save changes")
            }
        }.buttonStyle(AccentButtonStyle(theme: store.theme)).disabled(store.saving || store.readOnly)
            .accessibilityIdentifier("scheduleAlarm")
    }
    private var repeatControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Repeat")
                Spacer()
                Button {
                    store.state.settings.repeatDays = selectedDays.count == 7 ? [] : Array(1...7)
                } label: {
                    Label("Daily", systemImage: selectedDays.count == 7 ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                }.buttonStyle(.plain).foregroundStyle(store.theme.accent).accessibilityIdentifier("dailyRepeat")
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        var days = selectedDays
                        if days.contains(day) { days.removeAll { $0 == day } } else { days.append(day) }
                        store.state.settings.repeatDays = days.sorted()
                    } label: {
                        Text(["S", "M", "T", "W", "T", "F", "S"][day - 1])
                            .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(selectedDays.contains(day) ? store.theme.onAccent : store.theme.muted)
                            .background(selectedDays.contains(day) ? store.theme.accent : store.theme.field, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day - 1])
                        .accessibilityAddTraits(selectedDays.contains(day) ? .isSelected : [])
                }
            }
            Text(AlarmRoutine.summary(selectedDays)).font(.caption).foregroundStyle(store.theme.muted)
        }
    }
    private var selectedDays: [Int] { store.state.settings.repeatDays ?? Array(1...7) }
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.7).foregroundStyle(store.theme.muted)
    }
    private func soundLevelControls(showCheckButton: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Alarm volume")
                Spacer()
                Text("\(Int(((store.state.settings.soundLevel ?? 1) * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(store.theme.muted)
            }
            Slider(value: Binding(get: { store.state.settings.soundLevel ?? 1 }, set: { store.state.settings.soundLevel = $0 }), in: 0.1...1, step: 0.05)
                .tint(store.theme.accent).accessibilityLabel("Alarm volume")
            Toggle("Gradually increase volume", isOn: Binding(get: { store.state.settings.gradualVolume == true }, set: { store.state.settings.gradualVolume = $0 }))
                .font(.system(size: 13)).tint(store.theme.accent2)
            if showCheckButton {
                Button("Check alarm sound") { soundCheckOpen = true }
                    .font(.system(size: 13)).foregroundStyle(store.theme.accent)
            }
        }
    }
    private var soundCheckSheet: some View {
        SheetShell(title: "Check your alarm sound", theme: store.theme) {
            VStack(alignment: .leading, spacing: 24) {
                soundLevelControls(showCheckButton: false)
                HStack(spacing: 12) {
                    soundCheckButton(store.sound.previewing ? "Stop preview" : "Preview sound", identifier: "previewAlarmSound") { store.preview() }
                    soundCheckButton("Test a 5-second alarm", identifier: "testAlarmSound") {
                        store.sound.stop()
                        Task { await store.addAlarm(soundCheck: true); soundCheckOpen = false }
                    }.disabled(store.saving || store.readOnly)
                }
                Text("Start the test, then lock your iPhone to hear the selected volume and gradual increase.")
                    .font(.caption).foregroundStyle(store.theme.muted)
            }
        }
    }
    private func soundCheckButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 32)
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(store.theme.text.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.theme.border))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
    private var wakeUpTests: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { testsExpanded.toggle() }
            } label: {
                HStack {
                    sectionLabel("Wake-up tests")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(testsExpanded ? 90 : 0)).foregroundStyle(store.theme.muted)
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Wake-up tests")
                .accessibilityValue(testsExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Double tap to expand or collapse")
                .accessibilityIdentifier("wakeTestsDisclosure")
            if testsExpanded {
                testToggle("Typing test", detail: "Retype a random code", isOn: $store.state.settings.typing)
                if store.state.settings.typing {
                    HStack(spacing: 12) {
                        testWheel("Length of code", selection: optionBinding(\.typingCodeLength, default: 8), range: WakeTestOptions.codeLengths, identifier: "typingLengthPicker")
                        testWheel("Timer · seconds", selection: optionBinding(\.typingTimeLimit, default: 30), range: WakeTestOptions.typingTimes, identifier: "typingTimerPicker")
                    }
                }
                testToggle("Math test", detail: "Solve addition problems", isOn: Binding(
                    get: { store.state.settings.mathCount > 0 },
                    set: { store.state.settings.mathCount = $0 ? 3 : 0 }))
                if store.state.settings.mathCount > 0 {
                    HStack(spacing: 12) {
                        testWheel("How many problems?", selection: $store.state.settings.mathCount, range: 1...8, identifier: "mathProblemPicker")
                        testWheel("Timer per question · seconds", selection: optionBinding(\.mathTimeLimit, default: 10), range: WakeTestOptions.mathTimes, identifier: "mathTimerPicker")
                    }
                }
            }
        }
    }
    private func optionBinding(_ key: WritableKeyPath<AlarmSettings, Int?>, default fallback: Int) -> Binding<Int> {
        Binding(get: { store.state.settings[keyPath: key] ?? fallback }, set: { store.state.settings[keyPath: key] = $0 })
    }
    private func testWheel(_ title: String, selection: Binding<Int>, range: ClosedRange<Int>, identifier: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(store.theme.muted)
                .multilineTextAlignment(.center).frame(height: 30)
            LoopingNumberPicker(value: selection, range: range, label: title, identifier: identifier, color: UIColor(store.theme.text))
                .frame(height: 112).clipped()
        }.frame(maxWidth: .infinity).clipped()
    }
    private func modeButton(_ title: String, mode: AlarmMode) -> some View {
        Button { store.state.settings.mode = mode } label: {
            Text(title).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(store.state.settings.mode == mode ? store.theme.text : store.theme.muted)
                .background(store.state.settings.mode == mode ? store.theme.text.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(store.state.settings.mode == mode ? .isSelected : [])
            .disabled(editingID != nil && mode != (store.state.alarms.first(where: { $0.id == editingID })?.isTimer == true ? .timer : .time))
    }
    private var timeWheels: some View {
        NativeTimePicker(hour: $store.state.settings.hour, minute: $store.state.settings.minute,
                         use24Hour: store.state.settings.use24Hour, isLight: store.theme.isLight)
            .frame(maxWidth: .infinity).frame(height: 170).clipped()
            .background(store.theme.field, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(store.theme.border))
    }
    private var durationWheels: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                numberWheel("Hours", values: 0..<100, selection: durationBinding(unit: 3600, modulus: 100))
                numberWheel("Minutes", values: 0..<60, selection: durationBinding(unit: 60, modulus: 60))
                numberWheel("Seconds", values: 0..<60, selection: durationBinding(unit: 1, modulus: 60))
            }.background(store.theme.field, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(store.theme.border))
            DurationPresets(theme: store.theme) { store.state.settings.durationSeconds = $0 * 60 }
        }
    }
    private func durationBinding(unit: Int, modulus: Int) -> Binding<Int> {
        Binding(get: { store.state.settings.durationSeconds / unit % modulus }, set: { value in
            let current = store.state.settings.durationSeconds / unit % modulus
            store.state.settings.durationSeconds += (value - current) * unit
        })
    }
    private func numberWheel(_ label: String, values: Range<Int>, selection: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(label.uppercased()).font(.system(size: 9, weight: .medium)).tracking(0.7).foregroundStyle(store.theme.muted).padding(.top, 12)
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { value in Text(label == "Hours" ? String(value) : String(format: "%02d", value)).font(.system(size: 28, weight: .light)).tag(value) }
            }.pickerStyle(.wheel).frame(maxWidth: .infinity).frame(height: 120).clipped()
        }.frame(maxWidth: .infinity).clipped()
    }
    private func testToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 14) {
            Divider().overlay(store.theme.border)
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(store.theme.text)
                    Text(detail).font(.system(size: 12)).foregroundStyle(store.theme.muted)
                }
            }.tint(store.theme.accent2).accessibilityIdentifier(title == "Math test" ? "mathTestToggle" : "typingTestToggle")
        }
    }
    private var ringtoneSheet: some View {
        SheetShell(title: "Ringtone", theme: store.theme) {
            VStack(spacing: 8) {
                ringtoneActionRow("Use my own file", symbol: "folder", action: .file)
                ringtoneActionRow("Find more ringtones online", symbol: "globe", action: .online)
                Divider().overlay(store.theme.border).padding(.vertical, 8)
                ForEach(RingtoneCatalog.tones) { tone in soundRow(id: tone.id, name: tone.name) }
                ForEach(store.state.importedSounds) { sound in soundRow(id: sound.id, name: sound.name) }
            }
        }
    }
    private func ringtoneActionRow(_ title: String, symbol: String, action: RingtoneAction) -> some View {
        Button { ringtoneAction = action; ringtoneOpen = false } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.padding(16).foregroundStyle(store.theme.accent)
                .background(store.theme.card, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    private func soundRow(id: String, name: String) -> some View {
        Button {
            store.sound.stop(); store.state.settings.ringtoneID = id; ringtoneOpen = false
        } label: {
            HStack {
                Text(name).font(.system(size: 14))
                Spacer()
                if store.state.settings.ringtoneID == id { Image(systemName: "checkmark").foregroundStyle(store.theme.accent) }
            }.padding(16).background(store.theme.card, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(store.theme.text)
        }.buttonStyle(.plain).accessibilityAddTraits(store.state.settings.ringtoneID == id ? .isSelected : [])
    }
    private var onlineSheet: some View {
        SheetShell(title: "Find more ringtones", theme: store.theme) {
            VStack(alignment: .leading, spacing: 14) {
                Text("These sites have free sounds. Download one you like, close this window, then press Use my own file.")
                    .font(.system(size: 13)).foregroundStyle(store.theme.muted)
                providerLink("Mixkit", detail: "Free alarm sounds", url: "https://mixkit.co/free-sound-effects/alarm/")
                providerLink("Pixabay", detail: "Free sound effects", url: "https://pixabay.com/sound-effects/search/alarm/")
                providerLink("Zedge", detail: "Popular phone ringtones", url: "https://www.zedge.net/find/ringtones/alarm")
                Text("Imported clips must be under 2 MB and shorter than 30 seconds.").font(.caption).foregroundStyle(store.theme.muted)
            }
        }
    }
    private func providerLink(_ title: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(store.theme.text)
                Spacer()
                Text(detail).font(.system(size: 12)).foregroundStyle(store.theme.muted)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(store.theme.muted)
            }.padding(16).background(store.theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(store.theme.border))
        }.accessibilityIdentifier("ringtoneProvider\(title)")
    }
}

struct DurationPresets: View {
    let theme: AlarmTheme
    var select: (Int) -> Void
    @State private var width: CGFloat = 0
    private let choices: [(String, Int)] = [("5 min", 5), ("10 min", 10), ("30 min", 30), ("1 hour", 60)]
    private var count: Int {
        var total: CGFloat = 0
        for (index, choice) in choices.enumerated() {
            let natural = (choice.0 as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]).width + 24
            total += natural + (index == 0 ? 0 : 6)
            if total > width { return max(1, index) }
        }
        return choices.count
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { select(choices[index].1) } label: {
                    Text(choices[index].0).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .padding(.vertical, 10).frame(maxWidth: .infinity).foregroundStyle(theme.text)
                        .background(theme.text.opacity(0.065), in: Capsule()).overlay(Capsule().stroke(theme.border))
                }.buttonStyle(.plain)
            }
        }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
