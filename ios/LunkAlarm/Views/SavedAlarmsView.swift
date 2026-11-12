import SwiftUI

struct SavedAlarmsView: View {
    @Bindable var store: AlarmStore
    var returnToClock: () -> Void
    var add: (AlarmMode) -> Void
    var edit: (AlarmRecord) -> Void
    @State private var lastSwipe = Date.distantPast
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
                        HStack(spacing: 8) {
                            if alarm.isTimer { Text("Countdown") }
                            Image(systemName: alarm.isTimer ? "timer" : "alarm")
                            if alarm.typing { Image(systemName: "keyboard") }
                            if alarm.wakeGames?.puzzle == true { Image(systemName: "puzzlepiece") }
                            if alarm.wakeGames?.mines == true { Image(systemName: "burst") }
                            if alarm.wakeGames?.sudoku == true { Image(systemName: "square.grid.3x3") }
                            if alarm.mathCount > 0 { Label("\(alarm.mathCount)", systemImage: "plus.forwardslash.minus") }
                        }.font(.system(size: 11)).foregroundStyle(theme.muted)
                            .accessibilityIdentifier("alarmMetadata-\(alarm.id)")
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
