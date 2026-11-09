import AVFoundation
import Foundation

struct AudioArmingFailure: LocalizedError {
    let id: UUID
    let reason: String
    var errorDescription: String? { reason }
}

// Scheduled media playback with no silent keepalive, notification request,
// Now Playing metadata or AlarmKit alert. Background scheduling needs hardware
// validation; queued players cannot survive process termination or a reboot.
@MainActor
final class AudioAlarmService {
    private struct Entry {
        let loop: AVAudioPlayer
        let intro: AVAudioPlayer?
        let target: Date
        let definition: AlarmRecord
        func stop() { intro?.stop(); loop.stop() }
        func start() throws {
            let elapsed = Date().timeIntervalSince(target)
            let introduction = intro?.duration ?? 0
            if let intro, elapsed < introduction {
                intro.currentTime = max(0, elapsed)
                guard intro.play(atTime: intro.deviceCurrentTime + max(0.05, -elapsed)) else { throw NativeAlarmError.soundUnavailable }
            }
            // Only the introduction contains the fade. The steady loop keeps the
            // requested volume instead of fading from zero on every repetition.
            guard loop.play(atTime: loop.deviceCurrentTime + max(0.05, introduction - elapsed)) else {
                intro?.stop(); throw NativeAlarmError.soundUnavailable
            }
        }
    }
    private var entries: [UUID: Entry] = [:]
    static private(set) var hasArmedPlayers = false
    func schedule(_ alarm: AlarmRecord, at date: Date? = nil) throws {
        let target = date ?? alarm.target
        if let entry = entries[alarm.id], entry.target == target, entry.definition == alarm { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        guard let source = SoundService.url(filename: alarm.playbackSoundFilename ?? alarm.soundFilename) else { throw NativeAlarmError.soundUnavailable }
        let loop = try AVAudioPlayer(contentsOf: source)
        loop.numberOfLoops = -1
        loop.volume = Float(alarm.soundLevel ?? 1)
        guard loop.prepareToPlay() else { throw NativeAlarmError.soundUnavailable }
        var intro: AVAudioPlayer?
        if alarm.gradualVolume == true {
            guard let rendered = SoundService.url(filename: alarm.soundFilename) else { throw NativeAlarmError.soundUnavailable }
            intro = try AVAudioPlayer(contentsOf: rendered)
            intro?.numberOfLoops = 0; intro?.volume = 1
            guard intro?.prepareToPlay() == true else { throw NativeAlarmError.soundUnavailable }
        }
        let entry = Entry(loop: loop, intro: intro, target: target, definition: alarm)
        try entry.start()
        entries[alarm.id]?.stop()
        entries[alarm.id] = entry
        Self.hasArmedPlayers = true
    }
    func cancel(_ id: UUID) {
        entries.removeValue(forKey: id)?.stop()
        Self.hasArmedPlayers = !entries.isEmpty
    }
    func synchronize(_ records: [AlarmRecord], answeringID: UUID?) throws {
        let allowed = Set(records.filter { $0.isEnabled && $0.playbackEngine == .continuousAudio && $0.status != .notScheduled }.map(\.id))
        for id in Array(entries.keys) where !allowed.contains(id) { cancel(id) }
        for alarm in records where allowed.contains(alarm.id) && alarm.id != answeringID {
            if alarm.status == .scheduled {
                do { try schedule(alarm) }
                catch { throw AudioArmingFailure(id: alarm.id, reason: error.localizedDescription) }
            }
            // Preserve sounding entries throughout the unlock flow. A terminated
            // session is never claimed to have played while the app was closed.
        }
    }
    func resumeAfterInterruption() throws {
        guard !entries.isEmpty else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        for entry in entries.values { try entry.start() }
    }
}
