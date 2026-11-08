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
    private(set) var challenge: TimedWakeChallenge?
    private(set) var challengeSoundEnabled = false
    private(set) var finishing = false
    let sound = SoundService()
    private let repository: StateRepository
    private let service = NativeAlarmService()
    private var systemIDs = Set<UUID>()
    private var alertingIDs = Set<UUID>()
    private var isActive = false
    private var isUITesting = false
    private var muteOnReturn = false
    private var challengeTimer: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var watchdogTasks: [Task<Void, Never>] = []
    private var watchdogRevision = 0

    init() {
        var dataFolder = "LunkAlarm"
        #if DEBUG
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if uiTesting { dataFolder = "LunkAlarm-UI-Tests" }
        #endif
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(dataFolder)
        repository = StateRepository(url: folder.appendingPathComponent("state.json"))
        do { state = try repository.load() }
        catch {
            state = SavedState(); readOnly = true
            errorMessage = "\(error.localizedDescription) Existing iOS alarms are not changed."
        }
        #if DEBUG
        isUITesting = uiTesting
        if uiTesting { state = SavedState(); readOnly = false; errorMessage = nil }
        if uiTesting && ProcessInfo.processInfo.arguments.contains("--ui-math-alarm") {
            state.alarms = [AlarmRecord(target: Date().addingTimeInterval(-1), isTimer: true,
                ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep",
                typing: false, mathCount: 3, status: .needsChallenge)]
        }
        #endif
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
    func addAlarm(soundCheck: Bool = false) async {
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
            let target = soundCheck ? Date().addingTimeInterval(5) : settings.mode == .time
                ? try AlarmScheduling.nextTime(hour: settings.hour, minute: settings.minute)
                : try AlarmScheduling.countdown(seconds: settings.durationSeconds)
            let filename = try SoundService.alarmFilename(original: selectedSound.filename, level: settings.soundLevel ?? 1, gradual: settings.gradualVolume == true)
            var record = AlarmRecord(target: target, isTimer: soundCheck || settings.mode == .timer,
                ringtoneID: settings.ringtoneID, soundFilename: filename,
                soundName: selectedSound.name, typing: soundCheck ? false : settings.typing, mathCount: soundCheck ? 0 : settings.mathCount)
            record.playbackSoundFilename = selectedSound.filename
            record.soundLevel = settings.soundLevel ?? 1
            record.gradualVolume = settings.gradualVolume == true
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
        guard ringing?.id != alarm.id else { return }
        do {
            try stopNativeAlarms(alarm, onlyAlerting: false)
            var next = state; next.alarms.removeAll { $0.id == alarm.id }
            guard commit(next) else {
                if let index = state.alarms.firstIndex(where: { $0.id == alarm.id }) { state.alarms[index].status = .notScheduled }
                return
            }
            if ringing?.id == alarm.id { endChallengeSession() }
        } catch { errorMessage = "Could not cancel the iOS alarm: \(error.localizedDescription)" }
    }
    func preview() {
        if sound.previewing { sound.stop(); return }
        do {
            guard let selectedSound else { throw NativeAlarmError.soundUnavailable }
            try sound.play(filename: selectedSound.filename, preview: true, volume: Float(state.settings.soundLevel ?? 1), gradual: state.settings.gradualVolume == true)
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
    func setActive(_ active: Bool, backgrounded: Bool = false) {
        isActive = active
        if backgrounded { muteOnReturn = true }
        if active {
            refresh()
            if muteOnReturn, ringing?.hasTests == true { setChallengeSound(false) }
            muteOnReturn = false
        }
        else if sound.previewing { sound.stop() }
        // Real, audible wake-up-test playback can continue in the background.
        // Scheduled alerts remain owned by AlarmKit; there is no idle keepalive.
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
                  let alarm = next.alarms.first(where: { $0.nativeAlarmIDs.contains(id) }) else { continue }
            if pieces[0] == "stop" { stoppedIDs.insert(alarm.id) }
        }
        next.alarms = AlarmReconciliation.reconcile(next.alarms, systemIDs: systemIDs, stoppedIDs: stoppedIDs, now: Date())
        if next != state, !commit(next) { return }
        UserDefaults.standard.removeObject(forKey: AlarmIntentInbox.key)
        if !isActive {
            if let current = currentRecord, nativeAlertIsSounding(current) { sound.stop() }
            return
        }
        if let current = ringing {
            if !state.alarms.contains(where: { $0.id == current.id }) {
                endChallengeSession()
            } else {
                checkChallengeDeadline()
                if challengeSoundEnabled, let record = currentRecord, !nativeAlertIsSounding(record) { playChallengeSound(record) }
            }
        }
        if ringing == nil,
           let nextAlarm = orderedAlarms.first(where: { nativeAlertIsSounding($0) || $0.status == .needsChallenge }) {
            begin(nextAlarm)
        }
    }
    func begin(_ alarm: AlarmRecord) {
        guard !finishing else { return }
        sound.stop()
        ringing = alarm
        challenge = TimedWakeChallenge(typing: alarm.typing, mathCount: alarm.mathCount)
        challengeSoundEnabled = !alarm.hasTests
        if alarm.hasTests {
            var next = state
            if let index = next.alarms.firstIndex(where: { $0.id == alarm.id }) { next.alarms[index].status = .needsChallenge }
            guard commit(next) else { challengeSoundEnabled = true; return }
            do { try stopNativeAlarms(alarm, onlyAlerting: false) }
            catch { errorMessage = "Could not pause the system sound: \(error.localizedDescription)" }
            startChallengeTimer()
            armChallengeDeadline()
        } else if !nativeAlertIsSounding(alarm) { playChallengeSound(alarm) }
    }
    private func playChallengeSound(_ alarm: AlarmRecord) {
        guard !sound.isPlaying || sound.previewing else { return }
        do { try sound.play(filename: alarm.playbackSoundFilename ?? alarm.soundFilename, preview: false,
                            volume: Float(alarm.soundLevel ?? 1), gradual: alarm.gradualVolume == true) }
        catch { errorMessage = "Alarm audio could not play: \(error.localizedDescription)" }
    }
    func submitCode(_ value: String) -> Bool {
        let resetCount = challenge?.resetCount
        let correct = challenge?.submit(code: value) == true
        if resetCount != challenge?.resetCount { handleChallengeTimeout() }
        else if challenge?.complete == true { finishCurrent() }
        else if correct { armChallengeDeadline() }
        return correct
    }
    func submitMathDigits(_ value: String) -> WakeChallenge.DigitResult {
        let result = challenge?.submit(digits: value) ?? .incomplete
        if result == .timedOut { handleChallengeTimeout() }
        else if challenge?.complete == true { finishCurrent() }
        else if result == .correct { armChallengeDeadline() }
        return result
    }
    func finishCurrent() {
        guard let alarm = currentRecord, challenge?.complete == true, !finishing else { return }
        finishing = true
        challengeTimer?.cancel()
        watchdogRevision += 1
        let pending = watchdogTasks
        pending.forEach { $0.cancel() }
        Task {
            defer { finishing = false }
            // Let an in-flight system schedule finish/cancel before deleting its owner.
            for task in pending { await task.value }
            do {
                try stopNativeAlarms(currentRecord ?? alarm, onlyAlerting: false)
                var next = state; next.alarms.removeAll { $0.id == alarm.id }
                guard commit(next) else { return }
                endChallengeSession(); message = nil; refresh()
            } catch { errorMessage = "Could not stop the iOS alarm: \(error.localizedDescription)" }
        }
    }

    private var currentRecord: AlarmRecord? { state.alarms.first { $0.id == ringing?.id } }
    private func nativeAlertIsSounding(_ alarm: AlarmRecord) -> Bool { alarm.nativeAlarmIDs.contains { alertingIDs.contains($0) } }
    private func stopNativeAlarms(_ alarm: AlarmRecord, onlyAlerting: Bool) throws {
        guard !isUITesting else { return }
        let ids = Set(alarm.nativeAlarmIDs)
        for native in try service.manager.alarms where ids.contains(native.id) {
            if onlyAlerting && native.state != .alerting { continue }
            if native.state == .alerting { try service.stop(id: native.id) }
            else { try service.cancel(id: native.id) }
            systemIDs.remove(native.id); alertingIDs.remove(native.id)
        }
    }
    func setChallengeSound(_ enabled: Bool) {
        guard let alarm = currentRecord else { return }
        challengeSoundEnabled = enabled
        if enabled {
            if !nativeAlertIsSounding(alarm) { playChallengeSound(alarm) }
        } else {
            sound.stop()
            do { try stopNativeAlarms(alarm, onlyAlerting: true) }
            catch { errorMessage = "Could not pause alarm sound: \(error.localizedDescription)" }
        }
    }
    private func startChallengeTimer() {
        challengeTimer?.cancel()
        challengeTimer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                self?.checkChallengeDeadline()
            }
        }
    }
    private func checkChallengeDeadline() {
        // Avoid a mutating inout access to the observable challenge every 250 ms.
        // Only publish a change when a deadline actually expires.
        guard isActive, !finishing, let deadline = challenge?.deadline, Date() >= deadline,
              challenge?.expireIfNeeded() == true else { return }
        handleChallengeTimeout()
    }
    private func handleChallengeTimeout() {
        guard let alarm = currentRecord else { return }
        do { try stopNativeAlarms(alarm, onlyAlerting: true) }
        catch { errorMessage = error.localizedDescription }
        challengeSoundEnabled = true
        playChallengeSound(alarm)
        armChallengeDeadline()
    }
    private func armChallengeDeadline() {
        watchdogRevision += 1
        let revision = watchdogRevision
        watchdogTask?.cancel()
        guard !isUITesting, let deadline = challenge?.deadline, let alarm = currentRecord else { return }
        watchdogTask = Task {
            do {
                // Retain every in-flight ID in its owner's record until the session
                // ends, so a crash cannot leave an untracked system timeout alarm.
                let nativeID = UUID()
                var next = state
                guard let index = next.alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
                let previousIDs = next.alarms[index].challengeAlarmIDs ?? []
                next.alarms[index].challengeAlarmIDs = previousIDs + [nativeID]
                guard commit(next) else { return }
                let previous = Set(previousIDs)
                for native in try service.manager.alarms where previous.contains(native.id) {
                    try service.cancel(id: native.id)
                    systemIDs.remove(native.id); alertingIDs.remove(native.id)
                }
                guard !Task.isCancelled, watchdogRevision == revision else { return }
                var timeoutAlarm = alarm
                // Foreground checks enforce the exact deadline. A one-second
                // backup grace lets them replace this guard before iOS presents
                // a duplicate system alert over the answering screen.
                timeoutAlarm.id = nativeID; timeoutAlarm.target = deadline.addingTimeInterval(1)
                timeoutAlarm.challengeAlarmIDs = nil
                try await service.schedule(timeoutAlarm, tint: theme.accent)
                if Task.isCancelled || watchdogRevision != revision || ringing?.id != alarm.id {
                    try? service.cancel(id: nativeID)
                } else { systemIDs.insert(nativeID) }
            } catch {
                if !Task.isCancelled && watchdogRevision == revision {
                    errorMessage = "Could not schedule the test timeout with iOS: \(error.localizedDescription)"
                }
            }
        }
        if let watchdogTask { watchdogTasks.append(watchdogTask) }
    }
    private func endChallengeSession() {
        challengeTimer?.cancel(); challengeTimer = nil
        watchdogRevision += 1; watchdogTask?.cancel(); watchdogTask = nil
        watchdogTasks.forEach { $0.cancel() }; watchdogTasks.removeAll()
        sound.stop(); ringing = nil; challenge = nil; challengeSoundEnabled = false
    }
}
