import SwiftUI

struct SavedAlarmsView: View {
    @Bindable var store: AlarmStore
    var returnToClock: () -> Void
    var add: () -> Void
    var edit: (AlarmRecord) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: returnToClock) { Label("Clock", systemImage: "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(store.theme.muted)
                Text("Your alarms").font(.system(size: 30, weight: .bold)).accessibilityIdentifier("savedAlarmsTitle")
                Text(nextLabel).font(.system(size: 14)).foregroundStyle(store.theme.muted)
                if store.savedAlarms.isEmpty {
                    Text("No saved alarms yet. Tap + to add one.").foregroundStyle(store.theme.muted).padding(.vertical, 40)
                }
                ForEach(store.savedAlarms) { alarm in alarmCard(alarm) }
            }.padding(20).padding(.bottom, 100).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .gesture(AlarmNavigationSwipe(direction: .down, action: returnToClock))
        .overlay(alignment: .bottomTrailing) {
            Button(action: add) {
                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                    .foregroundStyle(store.theme.onAccent).frame(width: 64, height: 64)
                    .background(store.theme.gradient, in: Circle()).shadow(color: store.theme.accent2.opacity(0.25), radius: 12, y: 5)
            }.buttonStyle(.plain).padding(24).accessibilityLabel("New alarm").accessibilityIdentifier("newAlarmButton")
        }
    }
    private var nextLabel: String {
        guard let alarm = store.savedAlarms.first(where: { $0.isEnabled && $0.status != .notScheduled }) else { return "No upcoming alarms" }
        return "Next alarm " + alarm.target.formatted(date: .abbreviated, time: .shortened)
    }
    private func alarmCard(_ alarm: AlarmRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button { edit(alarm) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if !alarm.displayName.isEmpty { Text(alarm.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1) }
                        Text(alarm.timeDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: store.state.settings.use24Hour ? "en_GB" : "en_US"))))
                            .font(.system(size: 32, weight: .light)).monospacedDigit()
                            .foregroundStyle(alarm.isEnabled ? store.theme.text : store.theme.muted)
                        HStack(spacing: 8) {
                            Text(AlarmRoutine.summary(alarm.days))
                            Image(systemName: alarm.playbackEngine == .continuousAudio ? "waveform" : "alarm")
                            if alarm.typing { Image(systemName: "keyboard") }
                            if alarm.mathCount > 0 { Label("\(alarm.mathCount)", systemImage: "plus.forwardslash.minus") }
                        }.font(.system(size: 11)).foregroundStyle(store.theme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Edit \(alarm.accessibleName)")
                    .accessibilityIdentifier("editAlarm-\(alarm.id)")
                    .disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: { value in Task { await store.setEnabled(alarm, value) } }))
                    .labelsHidden().tint(store.theme.accent2).disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                    .accessibilityLabel("Enable \(alarm.accessibleName)")
            }
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { day in
                        Text(["S", "M", "T", "W", "T", "F", "S"][day - 1])
                            .font(.system(size: 11)).foregroundStyle(alarm.days.contains(day) ? store.theme.accent : store.theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }.frame(maxWidth: .infinity)
                Menu {
                    Button("Delete", role: .destructive) { store.remove(alarm) }
                    Button("Duplicate") { Task { await store.duplicate(alarm) } }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 30) }
                    .menuOrder(.fixed)
                    .disabled(store.saving || store.readOnly || store.ringing?.id == alarm.id)
                    .accessibilityLabel("Options for \(alarm.accessibleName)")
            }
            if alarm.status == .notScheduled && alarm.isEnabled {
                Text("Not scheduled. Turn off and on to retry.").font(.caption).foregroundStyle(store.theme.accent)
            }
            if alarm.status == .needsChallenge {
                Button("Finish wake-up tests") { store.begin(alarm) }.foregroundStyle(store.theme.accent)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 18).fill(store.theme.card).onTapGesture { if !store.saving && !store.readOnly && store.ringing?.id != alarm.id { edit(alarm) } } }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.theme.border).allowsHitTesting(false))
    }
}
