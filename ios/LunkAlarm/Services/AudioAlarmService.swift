import AVFoundation
import Foundation

// Public scheduled media playback, with no silent keepalive, notification request,
// Now Playing metadata or AlarmKit alert. Background scheduling must be verified
// on hardware; this service cannot survive process termination or a reboot.
struct AudioArmingFailure: LocalizedError {
    let id: UUID
    let reason: String
    var errorDescription: String? { reason }
}

@MainActor
final class AudioAlarmService {
    private struct Entry {
        let player: AVAudioPlayer
        let target: Date
        let filename: String
    }
    private var entries: [UUID: Entry] = [:]
    static private(set) var hasArmedPlayers = false
    func schedule(_ alarm: AlarmRecord, at date: Date? = nil) throws {
        let target = date ?? alarm.target
        if let entry = entries[alarm.id], entry.target == target, entry.filename == alarm.soundFilename { return }
        guard let url = SoundService.url(filename: alarm.soundFilename) else { throw NativeAlarmError.soundUnavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1; player.volume = 1
        guard player.prepareToPlay(), player.play(atTime: player.deviceCurrentTime + max(0.05, target.timeIntervalSinceNow)) else { throw NativeAlarmError.soundUnavailable }
        entries[alarm.id]?.player.stop()
        entries[alarm.id] = Entry(player: player, target: target, filename: alarm.soundFilename)
        Self.hasArmedPlayers = true
    }
    func cancel(_ id: UUID) {
        entries.removeValue(forKey: id)?.player.stop()
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
            // Preserve an already sounding entry while the user unlocks. A
            // suspended/terminated session is never claimed to be audible here.
        }
    }
    func resumeAfterInterruption() throws {
        guard !entries.isEmpty else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        for entry in entries.values where !entry.player.isPlaying {
            guard entry.player.play(atTime: entry.player.deviceCurrentTime + max(0.05, entry.target.timeIntervalSinceNow)) else { throw NativeAlarmError.soundUnavailable }
        }
    }
}
