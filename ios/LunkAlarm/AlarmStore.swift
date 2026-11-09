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
        if uiTesting && ProcessInfo.processInfo.arguments.contains("--ui-typing-alarm") {
            var alarm = AlarmRecord(target: Date().addingTimeInterval(-1), isTimer: true,
                ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep",
                typing: true, mathCount: 0, status: .needsChallenge)
            alarm.typingCodeLength = 4
            state.alarms = [alarm]
        }
        if uiTesting && ProcessInfo.processInfo.arguments.contains("--ui-mixed-alarms") {
            var routine = AlarmRecord(target: Date().addingTimeInterval(3600), isTimer: false,
                ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: false, mathCount: 0)
            routine.name = "Morning"; routine.repeatDays = Array(1...7)
            var timer = routine; timer.id = UUID(); timer.isTimer = true; timer.name = nil; timer.repeatDays = []; timer.durationSeconds = 1800
            timer.target = Date().addingTimeInterval(1800)
            state.alarms = [routine, timer]
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
        return switch authorization {
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
    @discardableResult
    func addAlarm(soundCheck: Bool = false, replacing id: UUID? = nil) async -> Bool {
        guard !readOnly, !saving, id == nil || ringing?.id != id else { return false }
        saving = true
        defer { saving = false }
        do {
            guard let selectedSound, SoundService.url(filename: selectedSound.filename) != nil else { throw NativeAlarmError.soundUnavailable }
            let settings = state.settings
            let original = id.flatMap { id in state.alarms.first { $0.id == id } }
            if id != nil && original == nil { return false }
            let target = soundCheck ? Date().addingTimeInterval(5) : settings.mode == .time
                ? try AlarmRoutine.next(hour: settings.hour, minute: settings.minute, days: settings.repeatDays ?? Array(1...7))
                : try AlarmScheduling.countdown(seconds: settings.durationSeconds)
            let filename = try SoundService.alarmFilename(original: selectedSound.filename, level: settings.soundLevel ?? 1, gradual: settings.gradualVolume == true)
            var record = AlarmRecord(id: id ?? UUID(), target: target, isTimer: soundCheck || settings.mode == .timer,
                ringtoneID: settings.ringtoneID, soundFilename: filename, soundName: selectedSound.name,
                typing: soundCheck ? false : settings.typing, mathCount: soundCheck ? 0 : settings.mathCount)
            record.durationSeconds = record.isTimer ? (soundCheck ? 5 : settings.durationSeconds) : nil
            record.enabled = original?.isEnabled ?? true
            if !record.isTimer {
                record.name = (settings.alarmName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                record.repeatDays = settings.repeatDays ?? Array(1...7)
                record.clockHour = settings.hour; record.clockMinute = settings.minute
            }
            record.playbackSoundFilename = selectedSound.filename
            record.soundLevel = settings.soundLevel ?? 1; record.gradualVolume = settings.gradualVolume == true
            record.typingCodeLength = settings.typingCodeLength; record.typingTimeLimit = settings.typingTimeLimit; record.mathTimeLimit = settings.mathTimeLimit
            return await persistDefinition(record, replacing: original)
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func loadEditor(_ alarm: AlarmRecord) {
        var settings = state.settings
        settings.mode = alarm.isTimer ? .timer : .time; settings.alarmName = alarm.name ?? ""
        if alarm.isTimer { settings.durationSeconds = alarm.durationSeconds ?? max(1, min(AlarmScheduling.maximumDuration, Int(ceil(alarm.target.timeIntervalSinceNow)))) }
        settings.repeatDays = alarm.days; settings.hour = alarm.clockHour ?? Calendar.current.component(.hour, from: alarm.target)
        settings.minute = alarm.clockMinute ?? Calendar.current.component(.minute, from: alarm.target)
        settings.ringtoneID = alarm.ringtoneID; settings.typing = alarm.typing; settings.mathCount = alarm.mathCount
        settings.soundLevel = alarm.soundLevel; settings.gradualVolume = alarm.gradualVolume
        settings.typingCodeLength = alarm.typingCodeLength; settings.typingTimeLimit = alarm.typingTimeLimit; settings.mathTimeLimit = alarm.mathTimeLimit
        state.settings = settings; message = nil; errorMessage = nil
    }
    func duplicate(_ alarm: AlarmRecord) async {
        guard !readOnly, !saving else { return }
        saving = true
        defer { saving = false }
        do { _ = await persistDefinition(try alarm.duplicated(), replacing: nil) }
        catch { errorMessage = error.localizedDescription }
    }
    private func prepared(_ original: AlarmRecord) -> AlarmRecord {
        var record = original
        record.engine = nil
        record.challengeAlarmIDs = recoveryDates(record).map { _ in UUID() }
        return record
    }
    private func recoveryDates(_ alarm: AlarmRecord) -> [Date] {
        guard alarm.isEnabled, alarm.hasTests else { return [] }
        return alarm.days.isEmpty ? AlarmRecovery.dates(after: alarm.target) : [60.0, 120, 180].map { alarm.target.addingTimeInterval($0) }
    }
    private func install(_ record: AlarmRecord) async throws {
        guard record.isEnabled else { return }
        if isUITesting { return }
        try await service.schedule(record, tint: theme.accent)
        for (id, date) in zip(record.challengeAlarmIDs ?? [], recoveryDates(record)) {
            try await service.schedule(recoveryRecord(record, id: id, date: date), tint: theme.accent)
        }
    }
    private func put(_ record: AlarmRecord, in next: inout SavedState) {
        if let index = next.alarms.firstIndex(where: { $0.id == record.id }) { next.alarms[index] = record }
        else { next.alarms.append(record) }
    }
    private func persistDefinition(_ definition: AlarmRecord, replacing original: AlarmRecord?) async -> Bool {
        let record = prepared(definition)
        do {
            if let original { try stopNativeAlarms(original, onlyAlerting: false) }
            var next = state; put(record, in: &next)
            guard commit(next) else {
                if let original { try? await install(original) }
                return false
            }
            do {
                try await install(record)
                message = record.isEnabled ? "Alarm set for " + record.target.formatted(date: .abbreviated, time: .shortened) + "." : "Alarm saved."
                return true
            } catch {
                let scheduleError = error
                // Keep ownership visible if system cancellation itself fails.
                do { try stopNativeAlarms(record, onlyAlerting: false) }
                catch {
                    var retained = state; var failed = record; failed.status = .notScheduled
                    put(failed, in: &retained); _ = commit(retained)
                    errorMessage = "Could not finish scheduling or cancel all alerts. Turn the alarm off or delete it to retry."
                    return false
                }
                var rollback = state; rollback.alarms.removeAll { $0.id == record.id }
                if var original {
                    do { try await install(original) }
                    catch { original.status = .notScheduled }
                    put(original, in: &rollback)
                }
                _ = commit(rollback)
                throw scheduleError
            }
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func remove(_ alarm: AlarmRecord) -> Bool {
        guard !readOnly, !saving, ringing?.id != alarm.id else { return false }
        do {
            try stopNativeAlarms(alarm, onlyAlerting: false)
            var next = state; next.alarms.removeAll { $0.id == alarm.id }
            guard commit(next) else {
                if let index = state.alarms.firstIndex(where: { $0.id == alarm.id }) { state.alarms[index].status = .notScheduled }
                return false
            }
            return true
        } catch { errorMessage = "Could not cancel the iOS alarm: \(error.localizedDescription)"; return false }
    }
    private func recoveryRecord(_ alarm: AlarmRecord, id: UUID, date: Date) -> AlarmRecord {
        var result = alarm
        result.id = id; result.target = date; result.challengeAlarmIDs = nil
        if alarm.days.isEmpty { result.repeatDays = [] }
        else {
            let calendar = Calendar.current
            let shift = calendar.dateComponents([.day], from: calendar.startOfDay(for: alarm.target), to: calendar.startOfDay(for: date)).day ?? 0
            result.repeatDays = alarm.days.map { ($0 - 1 + shift) % 7 + 1 }.sorted()
            result.clockHour = calendar.component(.hour, from: date)
            result.clockMinute = calendar.component(.minute, from: date)
        }
        return result
    }
    func setEnabled(_ alarm: AlarmRecord, _ enabled: Bool) async {
        guard !readOnly, !saving, ringing?.id != alarm.id,
              let original = state.alarms.first(where: { $0.id == alarm.id }) else { return }
        saving = true
        defer { saving = false }
        do {
            var record = original
            record.enabled = enabled; record.status = .scheduled
            if enabled {
                if record.isTimer { record.target = try AlarmScheduling.countdown(seconds: record.durationSeconds ?? max(1, min(AlarmScheduling.maximumDuration, Int(ceil(record.target.timeIntervalSinceNow))))) }
                else { record.target = try AlarmRoutine.next(hour: record.clockHour ?? Calendar.current.component(.hour, from: record.target), minute: record.clockMinute ?? Calendar.current.component(.minute, from: record.target), days: record.days) }
            }
            _ = await persistDefinition(record, replacing: original)
        } catch { errorMessage = error.localizedDescription }
    }
    // Upgrade alarms created with the removed experimental engine, preserving
    // their definitions/IDs. Existing system alarms and their recovery guards
    // never pass through this migration.
    private func migrateLegacyAudioAlarms() async {
        guard !readOnly, !saving else { return }
        saving = true
        defer { saving = false }
        for original in state.alarms where original.requiresSystemMigration {
            do {
                var record = original
                record.engine = nil
                if record.isEnabled && record.target <= Date() {
                    if record.hasTests { record.status = .needsChallenge }
                    record.target = record.isTimer ? Date().addingTimeInterval(5)
                        : try AlarmRoutine.next(hour: record.clockHour ?? Calendar.current.component(.hour, from: record.target), minute: record.clockMinute ?? Calendar.current.component(.minute, from: record.target), days: record.days)
                }
                _ = await persistDefinition(record, replacing: original)
            } catch { errorMessage = "Could not move an existing alarm to iOS: \(error.localizedDescription)" }
        }
    }
    func resumeAudioAfterInterruption() {
        if challengeSoundEnabled { sound.resumeAfterInterruption() }
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
        await migrateLegacyAudioAlarms()
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
        do {
            reconcile(service.manager.authorizationState == .authorized ? try service.manager.alarms : [])
        }
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
            if pieces[0] == "stop" || (pieces[0] == "open" && alarm.hasTests) { stoppedIDs.insert(alarm.id) }
        }
        next.alarms = AlarmReconciliation.reconcile(next.alarms, systemIDs: systemIDs, stoppedIDs: stoppedIDs, now: Date(), alertingIDs: alertingIDs)
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
           let nextAlarm = orderedAlarms.first(where: {  $0.isEnabled && (nativeAlertIsSounding($0) || $0.status == .needsChallenge) }) {
            begin(nextAlarm)
        }
    }
    func begin(_ alarm: AlarmRecord) {
        guard !finishing, alarm.isEnabled, !alarm.requiresSystemMigration else { return }
        sound.stop()
        ringing = alarm
        challenge = TimedWakeChallenge(typing: alarm.typing, mathCount: alarm.mathCount,
            codeLength: alarm.typingCodeLength ?? 8, typingTimeLimit: alarm.typingTimeLimit ?? 30,
            mathTimeLimit: alarm.mathTimeLimit ?? 10)
        challengeSoundEnabled = !alarm.hasTests
        if alarm.hasTests {
            var next = state
            if let index = next.alarms.firstIndex(where: { $0.id == alarm.id }) { next.alarms[index].status = .needsChallenge }
            guard commit(next) else { challengeSoundEnabled = true; return }
            // Quiet the current alert, but retain future recovery alerts until
            // iOS confirms their replacement question guards are scheduled.
            do { try stopNativeAlarms(alarm, onlyAlerting: true) }
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
                var next = state
                if alarm.isTimer { next.alarms.removeAll { $0.id == alarm.id } }
                else if let index = next.alarms.firstIndex(where: { $0.id == alarm.id }) {
                    next.alarms[index].enabled = false
                    next.alarms[index].challengeAlarmIDs = nil
                    next.alarms[index].status = .scheduled
                }
                guard commit(next) else { return }
                endChallengeSession(); message = nil
                if !alarm.isTimer && !alarm.days.isEmpty { await setEnabled(alarm, true) }
                refresh()
            } catch { errorMessage = "Could not stop the iOS alarm: \(error.localizedDescription)" }
        }
    }

    private var currentRecord: AlarmRecord? { state.alarms.first { $0.id == ringing?.id } }
    private func nativeAlertIsSounding(_ alarm: AlarmRecord) -> Bool { alarm.nativeAlarmIDs.contains { alertingIDs.contains($0) } }
    private func stopNativeAlarms(_ alarm: AlarmRecord, onlyAlerting: Bool) throws {
        guard !isUITesting, service.manager.authorizationState == .authorized else { return }
        let ids = Set(alarm.nativeAlarmIDs)
        for native in try service.manager.alarms where ids.contains(native.id) {
            if onlyAlerting && native.state != .alerting { continue }
            if native.state == .alerting {
                try service.stop(id: native.id)
                // Stopping a weekly occurrence may preserve its future schedule.
                // Delete/disable/completion must cancel that retained schedule too.
                if !onlyAlerting, try service.manager.alarms.contains(where: { $0.id == native.id }) {
                    try service.cancel(id: native.id)
                }
            } else { try service.cancel(id: native.id) }
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
                // Add the exact timeout plus bounded recovery alerts in advance.
                // A failed unlock cannot prevent already scheduled alerts firing.
                let first = deadline.addingTimeInterval(1)
                let dates = [first] + AlarmRecovery.dates(after: first)
                let nativeIDs = dates.map { _ in UUID() }
                var next = state
                guard let index = next.alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
                let previousIDs = next.alarms[index].challengeAlarmIDs ?? []
                next.alarms[index].challengeAlarmIDs = previousIDs + nativeIDs
                guard commit(next) else { return }
                for (offset, pair) in zip(nativeIDs, dates).enumerated() {
                    guard !Task.isCancelled, watchdogRevision == revision, ringing?.id == alarm.id else { return }
                    var timeoutAlarm = alarm
                    timeoutAlarm.id = pair.0; timeoutAlarm.target = pair.1
                    timeoutAlarm.challengeAlarmIDs = nil; timeoutAlarm.repeatDays = []
                    try await service.schedule(timeoutAlarm, tint: theme.accent)
                    systemIDs.insert(pair.0)
                    // A newer generation owns cleanup of older IDs. Leave these
                    // persisted guards armed until its own first guard is confirmed.
                    guard !Task.isCancelled, watchdogRevision == revision, ringing?.id == alarm.id else { return }
                    if offset == 0 {
                        // Replace the deadline first, then release predecessors.
                        // This avoids both a silence gap and doubling every backup
                        // slot while several user alarms are already scheduled.
                        let previous = Set(previousIDs)
                        for native in try service.manager.alarms where previous.contains(native.id) {
                            if native.state == .alerting { try service.stop(id: native.id) }
                            else { try service.cancel(id: native.id) }
                            systemIDs.remove(native.id); alertingIDs.remove(native.id)
                        }
                    }
                }
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
