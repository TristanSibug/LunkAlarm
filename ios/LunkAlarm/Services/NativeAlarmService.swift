import ActivityKit
// The iOS 26 SDK predates complete Sendable annotations on AlarmManager.
// All app-initiated access remains confined to this MainActor service.
@preconcurrency import AlarmKit
import AppIntents
import SwiftUI

@MainActor
struct NativeAlarmService {
    var manager: AlarmManager { .shared }
    func authorize() async throws {
        let state = manager.authorizationState == .notDetermined
            ? try await manager.requestAuthorization() : manager.authorizationState
        guard state == .authorized else { throw NativeAlarmError.permissionDenied }
    }
    func schedule(_ alarm: AlarmRecord, tint: Color) async throws {
        try await authorize()
        let stop = AlarmButton(text: alarm.hasTests ? "Wake-up tests" : "Stop", textColor: .white,
                               systemImageName: alarm.hasTests ? "arrow.up.right" : "stop.fill")
        let open = AlarmButton(text: "Open LunkAlarm",
                               textColor: .white, systemImageName: "arrow.up.right")
        let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(
            title: "\(alarm.isTimer ? alarm.soundName : alarm.displayName)", stopButton: stop, secondaryButton: alarm.hasTests ? nil : open,
            secondaryButtonBehavior: alarm.hasTests ? nil : .custom))
        let attributes = AlarmAttributes(presentation: presentation,
                                         metadata: LunkAlarmMetadata(soundName: alarm.soundName, hasTests: alarm.hasTests),
                                         tintColor: tint)
        let stopIntent: (any LiveActivityIntent)? = alarm.hasTests ? OpenWakeTestsIntent(id: alarm.id) : nil
        // Both modes use an absolute deadline, keeping our persisted deadline and iOS in sync.
        // No snooze/countdown controls: these are one-shot alarms, including relative durations.
        let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let schedule: Alarm.Schedule = !alarm.isTimer && !alarm.days.isEmpty
            ? .relative(.init(time: .init(hour: alarm.clockHour ?? Calendar.current.component(.hour, from: alarm.target), minute: alarm.clockMinute ?? Calendar.current.component(.minute, from: alarm.target)), repeats: .weekly(alarm.days.map { weekdays[$0 - 1] })))
            : .fixed(alarm.target)
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: schedule, attributes: attributes,
            stopIntent: stopIntent, secondaryIntent: alarm.hasTests ? nil : OpenLunkAlarmIntent(id: alarm.id),
            sound: .named(alarm.soundFilename))
        _ = try await manager.schedule(id: alarm.id, configuration: configuration)
    }
    func cancel(id: UUID) throws { try manager.cancel(id: id) }
    func stop(id: UUID) throws { try manager.stop(id: id) }
}

enum NativeAlarmError: LocalizedError {
    case permissionDenied, soundUnavailable, readOnly
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Allow Alarms for LunkAlarm in iPhone Settings before adding an alarm."
        case .soundUnavailable: "That sound is unavailable. Choose another ringtone or import the file again."
        case .readOnly: "Saved data could not be loaded safely. Adding or changing alarms is disabled to protect it."
        }
    }
}
