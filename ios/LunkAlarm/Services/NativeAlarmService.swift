import ActivityKit
import AlarmKit
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
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let open = AlarmButton(text: alarm.hasTests ? "Wake-up tests" : "Open LunkAlarm",
                               textColor: .white, systemImageName: "arrow.up.right")
        let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(
            title: "LunkAlarm", stopButton: stop, secondaryButton: open, secondaryButtonBehavior: .custom))
        let attributes = AlarmAttributes(presentation: presentation,
                                         metadata: LunkAlarmMetadata(soundName: alarm.soundName, hasTests: alarm.hasTests),
                                         tintColor: tint)
        let stopIntent: (any LiveActivityIntent)? = alarm.hasTests ? OpenWakeTestsIntent(id: alarm.id) : nil
        // Both modes use an absolute deadline, keeping our persisted deadline and iOS in sync.
        // No snooze/countdown controls: these are one-shot alarms, including relative durations.
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(alarm.target), attributes: attributes,
            stopIntent: stopIntent, secondaryIntent: OpenLunkAlarmIntent(id: alarm.id),
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
