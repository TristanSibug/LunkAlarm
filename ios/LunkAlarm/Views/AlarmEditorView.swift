import SwiftUI
import UniformTypeIdentifiers

struct AlarmEditorView: View {
    @Bindable var store: AlarmStore
    @State private var ringtoneOpen = false
    @State private var onlineOpen = false
    @State private var importing = false
    var body: some View {
        AlarmCard(theme: store.theme) {
            Text("New alarm").font(.system(size: 14, weight: .medium)).foregroundStyle(store.theme.muted)
            HStack(spacing: 4) {
                modeButton("At a time", mode: .time)
                modeButton("In how long", mode: .timer)
            }.padding(4).background(store.theme.field, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(store.state.settings.mode == .time ? "Ring at" : "Ring in")
                if store.state.settings.mode == .time { timeWheels } else { durationWheels }
            }
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
                Button("Use my own file") { importing = true }
                Button("Find more ringtones online") { onlineOpen = true }
            }.font(.system(size: 13)).foregroundStyle(store.theme.accent)
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("Wake-up tests")
                testToggle("Typing test", detail: "Type a random 8-character code to stop the alarm", isOn: $store.state.settings.typing)
                testToggle("Math test", detail: "Solve addition problems on a keypad to stop the alarm", isOn: Binding(
                    get: { store.state.settings.mathCount > 0 },
                    set: { store.state.settings.mathCount = $0 ? 3 : 0 }))
                if store.state.settings.mathCount > 0 {
                    Text("How many problems?").font(.caption).foregroundStyle(store.theme.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(1...8, id: \.self) { count in
                            Button { store.state.settings.mathCount = count } label: {
                                Text("\(count)").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .foregroundStyle(store.state.settings.mathCount == count ? store.theme.onAccent : store.theme.text)
                                    .background {
                                        if store.state.settings.mathCount == count { RoundedRectangle(cornerRadius: 12).fill(store.theme.gradient) }
                                        else { RoundedRectangle(cornerRadius: 12).fill(store.theme.field) }
                                    }
                            }.buttonStyle(.plain).accessibilityAddTraits(store.state.settings.mathCount == count ? .isSelected : [])
                        }
                    }
                }
                Text("Each alarm remembers its tests. Wake-up tests run in LunkAlarm; iOS can still stop alarms from the Lock Screen.")
                    .font(.system(size: 12)).foregroundStyle(store.theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(store.theme.accent) }
            Button {
                Task { await store.addAlarm() }
            } label: {
                HStack { if store.saving { ProgressView() }; Text(store.saving ? "Scheduling…" : "Add alarm") }
            }.buttonStyle(AccentButtonStyle(theme: store.theme)).disabled(store.saving || store.readOnly)
                .accessibilityIdentifier("scheduleAlarm")
        }
        .sheet(isPresented: $ringtoneOpen) { ringtoneSheet }
        .sheet(isPresented: $onlineOpen) { onlineSheet }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): store.importSound(url)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: store.state.settings.ringtoneID) { _, _ in if store.sound.previewing { store.sound.stop() } }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.7).foregroundStyle(store.theme.muted)
    }
    private func modeButton(_ title: String, mode: AlarmMode) -> some View {
        Button { store.state.settings.mode = mode } label: {
            Text(title).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(store.state.settings.mode == mode ? store.theme.text : store.theme.muted)
                .background(store.state.settings.mode == mode ? store.theme.text.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(store.state.settings.mode == mode ? .isSelected : [])
    }
    private var timeWheels: some View {
        HStack(spacing: 0) {
            if store.state.settings.use24Hour {
                numberWheel("Hours", values: 0..<24, selection: $store.state.settings.hour)
            } else {
                numberWheel("Hours", values: 1..<13, selection: Binding(
                    get: { let value = store.state.settings.hour % 12; return value == 0 ? 12 : value },
                    set: { store.state.settings.hour = $0 % 12 + (store.state.settings.hour >= 12 ? 12 : 0) }))
            }
            numberWheel("Minutes", values: 0..<60, selection: $store.state.settings.minute)
            if !store.state.settings.use24Hour {
                Picker("AM or PM", selection: Binding(
                    get: { store.state.settings.hour >= 12 ? 1 : 0 },
                    set: { store.state.settings.hour = store.state.settings.hour % 12 + $0 * 12 })) {
                    Text("AM").tag(0); Text("PM").tag(1)
                }.pickerStyle(.wheel).frame(maxWidth: .infinity).frame(height: 140).clipped()
            }
        }.background(store.theme.field, in: RoundedRectangle(cornerRadius: 16))
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
                ForEach(values, id: \.self) { value in Text(String(format: "%02d", value)).font(.system(size: 28, weight: .light)).tag(value) }
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
            }.tint(store.theme.accent2)
        }
    }
    private var ringtoneSheet: some View {
        SheetShell(title: "Ringtone", theme: store.theme) {
            VStack(spacing: 8) {
                ForEach(RingtoneCatalog.tones) { tone in soundRow(id: tone.id, name: tone.name) }
                ForEach(store.state.importedSounds) { sound in soundRow(id: sound.id, name: sound.name) }
            }
        }
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
        }
    }
}

struct DurationPresets: View {
    let theme: AlarmTheme
    var select: (Int) -> Void
    @State private var width: CGFloat = 0
    private let choices: [(String, Int)] = [("5 min", 5), ("10 min", 10), ("30 min", 30), ("1 hour", 60), ("8 hours", 480)]
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
