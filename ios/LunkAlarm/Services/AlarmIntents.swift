import AlarmKit
import AppIntents
import Foundation

// LiveActivityIntent executes in the app process; no shared-container entitlement is needed.
enum AlarmIntentInbox {
    static let key = "lunkalarm.intentEvents"
    static func record(id: String, stopped: Bool) {
        var events = UserDefaults.standard.stringArray(forKey: key) ?? []
        events.append((stopped ? "stop:" : "open:") + id)
        UserDefaults.standard.set(events, forKey: key)
        NotificationCenter.default.post(name: .lunkAlarmIntent, object: nil)
    }
}
extension Notification.Name {
    static let lunkAlarmIntent = Notification.Name("lunkalarm.intent")
}

struct OpenLunkAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open LunkAlarm"
    static let openAppWhenRun = true
    @Parameter(title: "Alarm ID") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        await MainActor.run { AlarmIntentInbox.record(id: alarmID, stopped: false) }
        return .result()
    }
}

struct OpenWakeTestsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open wake-up tests"
    static let openAppWhenRun = true
    @Parameter(title: "Alarm ID") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        try await MainActor.run {
            if let id = UUID(uuidString: alarmID), try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
                try AlarmManager.shared.stop(id: id)
            }
            AlarmIntentInbox.record(id: alarmID, stopped: true)
        }
        return .result()
    }
}
