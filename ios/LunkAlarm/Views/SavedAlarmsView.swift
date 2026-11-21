import SwiftUI

struct SavedAlarmsView: View {
    @Bindable var store: AlarmStore
    var returnToClock: () -> Void
    var add: (AlarmMode) -> Void
    var edit: (AlarmRecord) -> Void
    @State private var lastSwipe = Date.distantPast
    @State private var smartDuplicateAlarm: AlarmRecord?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: returnToClock) { Label("Clock", systemImage: "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(store.theme.muted)
                if store.orderedAlarms.isEmpty {
                    Text("Alarms & timers").font(.system(size: 30, weight: .bold)).accessibilityIdentifier("savedAlarmsTitle")
                    Text("No alarms or timers yet. Tap + to add one.").foregroundStyle(store.theme.muted).padding(.vertical, 40)
                }
                alarmSection(timer: true)
                alarmSection(timer: false)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).padding(.bottom, 100)
                .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .top)
        }
        .gesture(AlarmNavigationSwipe(direction: .down, action: returnToClock))
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button { add(.time) } label: { Label("Alarm", systemImage: "alarm.fill") }
                Button { add(.timer) } label: { Label("Timer", systemImage: "timer") }
            } label: {
                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                    .foregroundStyle(store.theme.onAccent).frame(width: 64, height: 64)
                    .background(store.theme.gradient, in: Circle()).shadow(color: store.theme.accent2.opacity(0.25), radius: 12, y: 5)
            }.buttonStyle(.plain).padding(24).accessibilityLabel("New alarm").accessibilityIdentifier("newAlarmButton")
        }
        .sheet(item: $smartDuplicateAlarm) { alarm in
            SmartDuplicateSheet(store: store, alarm: alarm)
        }
        .onChange(of: store.ringing?.id) { _, id in
            if id != nil { smartDuplicateAlarm = nil }
        }
    }
    @ViewBuilder private func alarmSection(timer: Bool) -> some View {
        let alarms = store.orderedAlarms.filter { $0.isTimer == timer }
        if !alarms.isEmpty {
            Text(timer ? "Timers" : "Alarms").font(.system(size: 30, weight: .bold)).accessibilityIdentifier(timer ? "timersTitle" : "savedAlarmsTitle")
            if let next = alarms.first(where: { $0.isEnabled && $0.status != .notScheduled }) {
                Text("Next " + (timer ? "timer " : "alarm ") + next.target.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 14)).foregroundStyle(store.theme.muted)
            }
            ForEach(alarms) { alarm in
                SwipeDeleteAlarmRow(enabled: canChange(alarm), name: alarm.accessibleName, delete: { store.remove(alarm) }, onSwipe: { lastSwipe = Date() }) { alarmCard(alarm) }
            }
        }
    }
    private func openEditor(_ alarm: AlarmRecord) {
        guard canChange(alarm), Date().timeIntervalSince(lastSwipe) > 0.3 else { return }
        edit(alarm)
    }
    private func canChange(_ alarm: AlarmRecord) -> Bool { !store.saving && !store.readOnly && store.ringing?.id != alarm.id }
    private var nextLabel: String {
        guard let alarm = store.orderedAlarms.first(where: { $0.isEnabled && $0.status != .notScheduled }) else { return "No upcoming alarms" }
        return "Next alarm " + alarm.target.formatted(date: .abbreviated, time: .shortened)
    }
    private func alarmCard(_ alarm: AlarmRecord) -> some View {
        let theme = store.theme.alarmCardTheme
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button { openEditor(alarm) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if !alarm.displayName.isEmpty { Text(alarm.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1) }
                        Group {
                            if alarm.isTimer {
                                Text(timerInterval: Date.distantPast...alarm.target, countsDown: true)
                            } else {
                                Text(alarm.timeDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: store.state.settings.use24Hour ? "en_GB" : "en_US"))))
                            }
                        }.font(.system(size: 32, weight: .light)).monospacedDigit()
                            .foregroundStyle(alarm.isEnabled ? theme.text : theme.muted)
                        if alarm.isTimer || alarm.hasTests {
                            HStack(spacing: 8) {
                                if alarm.isTimer { Text("Countdown") }
                                if alarm.typing { Image(systemName: "keyboard") }
                                if alarm.wakeGames?.puzzle == true { Image(systemName: "puzzlepiece") }
                                if alarm.wakeGames?.mines == true { Image(systemName: "burst") }
                                if alarm.wakeGames?.sudoku == true { Image(systemName: "square.grid.3x3") }
                                if alarm.wakeGames?.stroop == true { Image(systemName: "paintpalette") }
                                if alarm.mathCount > 0 { Image(systemName: "plus.forwardslash.minus").accessibilityLabel("Math") }
                            }.font(.system(size: 11)).foregroundStyle(theme.muted)
                                .accessibilityIdentifier("alarmMetadata-\(alarm.id)")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Edit \(alarm.accessibleName)")
                    .accessibilityIdentifier("editAlarm-\(alarm.id)")
                    .disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                if !alarm.isTimer {
                Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: { value in Task { await store.setEnabled(alarm, value) } }))
                    .labelsHidden().tint(theme.accent2).disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                    .accessibilityLabel("Enable \(alarm.accessibleName)")
                }
            }
            HStack(spacing: 8) {
                if alarm.isTimer {
                    Text("Rings at " + alarm.target.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                } else if alarm.days.count == 7 {
                    Text("Daily").font(.system(size: 12)).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("alarmDaily-\(alarm.id)")
                } else {
                    HStack(spacing: 0) {
                        ForEach(1...7, id: \.self) { day in
                            let selected = alarm.days.contains(day)
                            Text(["S", "M", "T", "W", "T", "F", "S"][day - 1])
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? theme.dayAccent : theme.muted)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(selected ? theme.dayAccent.opacity(0.08) : .clear))
                                .overlay(Circle().strokeBorder(selected ? theme.dayAccent : .clear, lineWidth: 1.3))
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day - 1])
                                .accessibilityValue(selected ? "Selected" : "Not selected")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityIdentifier("alarmDay-\(alarm.id)-\(day)")
                        }
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("alarmWeekdays-\(alarm.id)")
                }
                Menu {
                    Button("Delete", role: .destructive) { store.remove(alarm) }
                    Button("Duplicate") { Task { await store.duplicate(alarm) } }
                    if !alarm.isTimer {
                        Button("Smart Duplicate") { smartDuplicateAlarm = alarm }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(theme.text).frame(width: 44, height: 30) }
                    .menuOrder(.fixed)
                    .disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                    .accessibilityLabel("Options for \(alarm.accessibleName)")
            }
            if alarm.status == .notScheduled && alarm.isEnabled {
                Text("Not scheduled. Turn off and on to retry.").font(.caption).foregroundStyle(theme.accent)
            }
            if alarm.status == .needsChallenge {
                Button("Finish wake-up tests") { store.begin(alarm) }.foregroundStyle(theme.accent)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 18).fill(theme.card).onTapGesture { openEditor(alarm) } }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.border).allowsHitTesting(false))
    }
}

private struct SmartDuplicateSheet: View {
    let store: AlarmStore
    let alarm: AlarmRecord
    @Environment(\.dismiss) private var dismiss
    @State private var count = 1
    @State private var useHours = false
    @State private var minutes = "5"
    @State private var hours = "1"
    @State private var copyTests = false
    @State private var showTestsHelp = false
    @State private var failure: String?
    private var intervalRange: ClosedRange<Int> {
        useHours ? AlarmRecord.smartDuplicateHourIntervals : AlarmRecord.smartDuplicateMinuteIntervals
    }
    private var intervalText: Binding<String> {
        Binding(get: { useHours ? hours : minutes }, set: { value in
            let digits = value.filter { $0.isASCII && $0.isNumber }
            if useHours { hours = digits } else { minutes = digits }
        })
    }
    private var intervalMinutes: Int? {
        guard let value = Int(intervalText.wrappedValue), intervalRange.contains(value) else { return nil }
        return useHours ? value * 60 : value
    }

    var body: some View {
        SheetShell(title: "Smart Duplicate", theme: store.theme, showsDone: false,
                   closeLabel: "Close Smart Duplicate", closeDisabled: store.saving) {
            VStack(alignment: .leading, spacing: 22) {
                Stepper("Duplicates: \(count)", value: $count, in: AlarmRecord.smartDuplicateCounts)
                    .accessibilityIdentifier("smartDuplicateCount")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Time between alarms").font(.subheadline)
                    Picker("Interval unit", selection: $useHours) {
                        Text("Minutes").tag(false)
                        Text("Hours").tag(true)
                    }.pickerStyle(.segmented)
                    HStack {
                        TextField(useHours ? "1–23 hours" : "1–59 minutes", text: intervalText)
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(useHours ? "Hours apart" : "Minutes apart")
                            .accessibilityIdentifier("smartDuplicateInterval")
                        Stepper("Interval", value: Binding(get: {
                            min(intervalRange.upperBound, max(intervalRange.lowerBound, Int(intervalText.wrappedValue) ?? 1))
                        }, set: { intervalText.wrappedValue = String($0) }), in: intervalRange)
                        .labelsHidden()
                    }
                    Text(useHours ? "1–23 hours" : "1–59 minutes").font(.caption).foregroundStyle(store.theme.muted)
                }
                if alarm.hasTests {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Which alarms should use the wake-up tests?").font(.subheadline)
                            Button { showTestsHelp = true } label: {
                                Image(systemName: "questionmark.circle").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).foregroundStyle(store.theme.accent)
                                .accessibilityLabel("How wake-up tests queue")
                        }
                        Picker("Wake-up tests", selection: $copyTests) {
                            Text("Original only").tag(false)
                            Text("All alarms").tag(true)
                        }.pickerStyle(.segmented)
                    }
                }
                if let failure { Text(failure).font(.callout).foregroundStyle(store.theme.accent) }
                Button(store.saving ? "Creating…" : count == 1 ? "Create 1 duplicate" : "Create \(count) duplicates") {
                    guard let intervalMinutes else { return }
                    Task {
                        failure = nil
                        if await store.smartDuplicate(alarm.id, count: count, intervalMinutes: intervalMinutes, copyTests: copyTests) {
                            dismiss()
                        } else {
                            failure = store.errorMessage ?? "Could not duplicate this alarm."
                            store.errorMessage = nil
                        }
                    }
                }.buttonStyle(AccentButtonStyle(theme: store.theme))
                    .disabled(store.saving || store.readOnly || intervalMinutes == nil)
            }
        }
        .interactiveDismissDisabled(store.saving)
        .alert("Queued wake-up tests", isPresented: $showTestsHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Wake-up tests queue up as alarms ring. Finish the current set to start the next one. Choose Original only to keep wake-up tests on the first alarm.")
        }
    }
}
