import AlarmKit
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AlarmStore {
    var state: SavedState
    var message: String?
    var errorMessage: String?
    private(set) var readOnly = false
    private(set) var saving = false
    private(set) var authorization = AlarmManager.shared.authorizationState
    private(set) var ringing: AlarmRecord?
    var challenge: WakeChallenge?
    let sound = SoundService()
    private let repository: StateRepository
    private let service = NativeAlarmService()
    private var systemIDs = Set<UUID>()
    private var alertingIDs = Set<UUID>()
    private var isActive = true

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LunkAlarm")
        repository = StateRepository(url: folder.appendingPathComponent("state.json"))
        do { state = try repository.load() }
        catch {
            state = SavedState(); readOnly = true
            errorMessage = "\(error.localizedDescription) Existing iOS alarms are not changed."
        }
    }
    var theme: AlarmTheme { AlarmTheme.find(state.settings.themeID) }
    var orderedAlarms: [AlarmRecord] { state.alarms.sorted { $0.target < $1.target } }
    var selectedSound: (name: String, filename: String)? {
        if let tone = RingtoneCatalog.tones.first(where: { $0.id == state.settings.ringtoneID }) {
            return (tone.name, tone.filename)
        }
        if let imported = state.importedSounds.first(where: { $0.id == state.settings.ringtoneID }) {
            return (imported.name, imported.filename)
        }
        return nil
    }
    var authorizationLabel: String {
        switch authorization {
        case .authorized: "Alarms allowed"
        case .denied: "Alarms disabled"
        case .notDetermined: "iPhone system time"
        @unknown default: "Check alarm access"
        }
    }

    @discardableResult private func commit(_ next: SavedState) -> Bool {
        guard !readOnly else { errorMessage = NativeAlarmError.readOnly.localizedDescription; return false }
        do { try repository.save(next); state = next; return true }
        catch { errorMessage = "Could not save changes: \(error.localizedDescription)"; return false }
    }
    func saveSettings() {
        guard !readOnly else { return }
        do { try repository.save(state) }
        catch { errorMessage = "Could not save preferences: \(error.localizedDescription)" }
    }
    func addAlarm() async {
        guard !readOnly, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            guard let selectedSound, SoundService.url(filename: selectedSound.filename) != nil else {
                throw NativeAlarmError.soundUnavailable
            }
            try await service.authorize()
            authorization = service.manager.authorizationState
            let settings = state.settings
            let target = settings.mode == .time
                ? try AlarmScheduling.nextTime(hour: settings.hour, minute: settings.minute)
                : try AlarmScheduling.countdown(seconds: settings.durationSeconds)
            let record = AlarmRecord(target: target, isTimer: settings.mode == .timer,
                ringtoneID: settings.ringtoneID, soundFilename: selectedSound.filename,
                soundName: selectedSound.name, typing: settings.typing, mathCount: settings.mathCount)
            // Persist first, then ask iOS to schedule. A crash between the two leaves a
            // visible 'Not scheduled' record, never an invisible OS alarm.
            var next = state; next.alarms.append(record)
            guard commit(next) else { return }
            do {
                try await service.schedule(record, tint: theme.accent)
                systemIDs.insert(record.id)
                message = "Alarm set for " + record.target.formatted(date: .abbreviated, time: .shortened) + "."
            } catch {
                var rollback = state; rollback.alarms.removeAll { $0.id == record.id }
                if !commit(rollback), let index = state.alarms.firstIndex(where: { $0.id == record.id }) {
                    state.alarms[index].status = .notScheduled
                }
                throw error
            }
        } catch {
            authorization = service.manager.authorizationState
            errorMessage = error.localizedDescription
        }
    }
    func remove(_ alarm: AlarmRecord) {
        guard !readOnly, !saving else { return }
        do {
            if systemIDs.contains(alarm.id) { try service.cancel(id: alarm.id) }
            systemIDs.remove(alarm.id); alertingIDs.remove(alarm.id)
            var next = state; next.alarms.removeAll { $0.id == alarm.id }
            guard commit(next) else {
                if let index = state.alarms.firstIndex(where: { $0.id == alarm.id }) { state.alarms[index].status = .notScheduled }
                return
            }
            if ringing?.id == alarm.id { sound.stop(); ringing = nil; challenge = nil }
        } catch { errorMessage = "Could not cancel the iOS alarm: \(error.localizedDescription)" }
    }
    func preview() {
        if sound.previewing { sound.stop(); return }
        do {
            guard let selectedSound else { throw NativeAlarmError.soundUnavailable }
            try sound.play(filename: selectedSound.filename, preview: true)
        } catch { errorMessage = error.localizedDescription }
    }
    func importSound(_ url: URL) {
        guard !readOnly else { return }
        do {
            let imported = try SoundService.importSound(from: url)
            var next = state
            next.importedSounds.append(imported); next.settings.ringtoneID = imported.id
            if !commit(next) {
                try? FileManager.default.removeItem(at: SoundService.soundsDirectory.appendingPathComponent(imported.filename))
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func observeAlarms() async {
        refresh()
        for await alarms in service.manager.alarmUpdates {
            if Task.isCancelled { return }
            reconcile(alarms)
        }
    }
    func observeAuthorization() async {
        for await newState in service.manager.authorizationUpdates {
            if Task.isCancelled { return }
            authorization = newState
        }
    }
    func setActive(_ active: Bool) {
        isActive = active
        if active { refresh() }
        else { sound.stop() } // AlarmKit, not a background audio loop, owns background alerts.
    }
    func refresh() {
        authorization = service.manager.authorizationState
        guard !saving else { return }
        do { reconcile(try service.manager.alarms) }
        catch { errorMessage = "Could not read iOS alarms: \(error.localizedDescription)" }
    }
    private func reconcile(_ nativeAlarms: [Alarm]) {
        systemIDs = Set(nativeAlarms.map(\.id))
        alertingIDs = Set(nativeAlarms.filter { $0.state == .alerting }.map(\.id))
        guard !readOnly, !saving else { return }
        var next = state
        let events = UserDefaults.standard.stringArray(forKey: AlarmIntentInbox.key) ?? []
        var stoppedIDs = Set<UUID>()
        for event in events {
            let pieces = event.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2, let id = UUID(uuidString: String(pieces[1])),
                  next.alarms.contains(where: { $0.id == id }) else { continue }
            if pieces[0] == "stop" { stoppedIDs.insert(id) }
        }
        next.alarms = AlarmReconciliation.reconcile(next.alarms, systemIDs: systemIDs, stoppedIDs: stoppedIDs, now: Date())
        if next != state, !commit(next) { return }
        UserDefaults.standard.removeObject(forKey: AlarmIntentInbox.key)
        guard isActive else { return }
        if let current = ringing {
            if !state.alarms.contains(where: { $0.id == current.id }) {
                sound.stop(); ringing = nil; challenge = nil
            } else if !alertingIDs.contains(current.id), !sound.previewing {
                playChallengeSound(current)
            }
        }
        if ringing == nil,
           let nextAlarm = orderedAlarms.first(where: { alertingIDs.contains($0.id) || $0.status == .needsChallenge }) {
            begin(nextAlarm)
        }
    }
    func begin(_ alarm: AlarmRecord) {
        sound.stop()
        ringing = alarm
        challenge = WakeChallenge(typing: alarm.typing, mathCount: alarm.mathCount)
        if !alertingIDs.contains(alarm.id) { playChallengeSound(alarm) }
    }
    private func playChallengeSound(_ alarm: AlarmRecord) {
        do { try sound.play(filename: alarm.soundFilename, preview: false) }
        catch { errorMessage = "Alarm audio could not play: \(error.localizedDescription)" }
    }
    func submitCode(_ value: String) -> Bool {
        guard challenge?.submit(code: value) == true else { return false }
        if challenge?.complete == true { finishCurrent() }
        return true
    }
    func submitAnswer(_ value: String) -> Bool {
        guard let answer = Int(value), challenge?.submit(answer: answer) == true else { return false }
        if challenge?.complete == true { finishCurrent() }
        return true
    }
    func finishCurrent() {
        guard let alarm = ringing, challenge?.complete == true else { return }
        do {
            if systemIDs.contains(alarm.id) { try service.stop(id: alarm.id) }
            systemIDs.remove(alarm.id); alertingIDs.remove(alarm.id)
            var next = state; next.alarms.removeAll { $0.id == alarm.id }
            guard commit(next) else { return }
            sound.stop(); ringing = nil; challenge = nil
            message = "Alarm dismissed. Have a good day."
            refresh()
        } catch { errorMessage = "Could not stop the iOS alarm: \(error.localizedDescription)" }
    }
}
