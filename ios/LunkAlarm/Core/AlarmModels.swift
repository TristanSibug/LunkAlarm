import Foundation

public enum AlarmMode: String, Codable, CaseIterable, Sendable {
    case time, timer
}

public struct ImportedSound: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var filename: String
    public init(id: String, name: String, filename: String) {
        self.id = id; self.name = name; self.filename = filename
    }
}

public struct AlarmSettings: Codable, Equatable, Sendable {
    public var alarmName: String?
    public var repeatDays: [Int]?
    public var themeID = "sunrise"
    public var use24Hour = false
    public var mode = AlarmMode.time
    public var ringtoneID = "classic-beep"
    public var typing = false
    public var mathCount = 0
    public var durationSeconds = 1800
    public var hour = 7
    public var minute = 0
    // Optional fields preserve compatibility with state saved before sound checks existed.
    public var soundLevel: Double?
    public var soundCheckCompleted: Bool?
    public var gradualVolume: Bool?
    public var typingCodeLength: Int?
    public var typingTimeLimit: Int?
    public var mathTimeLimit: Int?
    public var wakeGames: WakeGameOptions?
    public var nativeMathKeyboard: Bool?
    public var vibrateInApp: Bool?
    public init() {}
}

public struct AlarmRecord: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case scheduled, needsChallenge, notScheduled }
    public var id: UUID
    public var target: Date
    public var isTimer: Bool
    public var ringtoneID: String
    public var soundFilename: String
    public var soundName: String
    public var typing: Bool
    public var mathCount: Int
    public var status: Status
    public var playbackSoundFilename: String?
    public var soundLevel: Double?
    public var gradualVolume: Bool?
    public var typingCodeLength: Int?
    public var typingTimeLimit: Int?
    public var mathTimeLimit: Int?
    public var wakeGames: WakeGameOptions?
    public var nativeMathKeyboard: Bool?
    public var vibrateInApp: Bool?
    // Decode the removed 1.4 playback preference only to migrate existing records.
    // Every new/edited alarm is scheduled exclusively through AlarmKit.
    public var engine: String?
    public var requiresSystemMigration: Bool { engine == "continuousAudio" }
    public var durationSeconds: Int?
    public var name: String?
    public var repeatDays: [Int]?
    public var enabled: Bool?
    public var clockHour: Int?
    public var clockMinute: Int?
    public var isEnabled: Bool { enabled != false }
    public var displayName: String { name ?? (isTimer ? "Timer" : "Alarm") }
    public var accessibleName: String { displayName.isEmpty ? "Alarm" : displayName }
    public var timeDate: Date {
        Calendar.current.date(bySettingHour: clockHour ?? Calendar.current.component(.hour, from: target), minute: clockMinute ?? Calendar.current.component(.minute, from: target), second: 0, of: Date()) ?? target
    }
    public func duplicated(now: Date = Date(), calendar: Calendar = .current) throws -> AlarmRecord {
        var copy = self
        copy.id = UUID(); copy.challengeAlarmIDs = nil; copy.status = .scheduled
        if isTimer {
            let seconds = durationSeconds ?? min(AlarmScheduling.maximumDuration, max(1, Int(ceil(target.timeIntervalSince(now)))))
            copy.target = try AlarmScheduling.countdown(seconds: seconds, now: now)
            copy.durationSeconds = seconds
        } else { copy.target = try AlarmRoutine.next(hour: clockHour ?? calendar.component(.hour, from: target), minute: clockMinute ?? calendar.component(.minute, from: target), days: days, now: now, calendar: calendar) }
        return copy
    }
    public var days: [Int] { repeatDays ?? [] }
    public var challengeAlarmIDs: [UUID]?
    public var nativeAlarmIDs: [UUID] { [id] + (challengeAlarmIDs ?? []) }
    public var hasTests: Bool { typing || mathCount > 0 || wakeGames?.hasTests == true }
    public init(id: UUID = UUID(), target: Date, isTimer: Bool, ringtoneID: String,
                soundFilename: String, soundName: String, typing: Bool, mathCount: Int,
                status: Status = .scheduled) {
        self.id = id; self.target = target; self.isTimer = isTimer; self.ringtoneID = ringtoneID
        self.soundFilename = soundFilename; self.soundName = soundName
        self.typing = typing; self.mathCount = mathCount; self.status = status
    }
}

public struct SavedState: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = AlarmSettings()
    public var alarms: [AlarmRecord] = []
    public var importedSounds: [ImportedSound] = []
    public var challengeSession: SavedChallengeSession?
    public init() {}

    public func validated() throws -> SavedState {
        guard version == 1 else { throw AlarmDataError.unsupportedVersion }
        guard Set(alarms.map(\.id)).count == alarms.count,
              settings.wakeGames?.valid != false, alarms.allSatisfy({ $0.wakeGames?.valid != false }),
              challengeSession.map({ session in session.challenge.valid && alarms.contains { $0.id == session.owner && $0.hasTests && $0.isEnabled } }) ?? true,
              Set(importedSounds.map(\.id)).count == importedSounds.count,
              (0...8).contains(settings.mathCount), (0...23).contains(settings.hour),
              (0...59).contains(settings.minute),
              AlarmRoutine.validDays(settings.repeatDays),
              alarms.allSatisfy({ AlarmRoutine.validDays($0.repeatDays) && ($0.clockHour.map { (0...23).contains($0) } ?? true) && ($0.clockMinute.map { (0...59).contains($0) } ?? true) }),
              WakeTestOptions.valid(codeLength: settings.typingCodeLength, typingTime: settings.typingTimeLimit, mathTime: settings.mathTimeLimit),
              settings.soundLevel.map({ (0.1...1).contains($0) }) ?? true,
              (0...AlarmScheduling.maximumDuration).contains(settings.durationSeconds),
              alarms.allSatisfy({ $0.durationSeconds.map({ (1...AlarmScheduling.maximumDuration).contains($0) }) ?? true }),
              alarms.allSatisfy({ (0...8).contains($0.mathCount) && Self.safeFilename($0.soundFilename) }),
              alarms.allSatisfy({ $0.playbackSoundFilename.map(Self.safeFilename) ?? true }),
              alarms.allSatisfy({ WakeTestOptions.valid(codeLength: $0.typingCodeLength, typingTime: $0.typingTimeLimit, mathTime: $0.mathTimeLimit) }),
              alarms.allSatisfy({ $0.soundLevel.map({ (0.1...1).contains($0) }) ?? true }),
              Set(alarms.flatMap(\.nativeAlarmIDs)).count == alarms.flatMap(\.nativeAlarmIDs).count,
              importedSounds.allSatisfy({ Self.safeFilename($0.filename) })
        else { throw AlarmDataError.invalidData }
        return self
    }
    private static func safeFilename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        value == URL(fileURLWithPath: value).lastPathComponent && !value.contains("\\")
    }
}

public enum AlarmDataError: LocalizedError {
    case unsupportedVersion, invalidData, invalidDuration, invalidTime
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This alarm data was saved by a newer app version. It has been left untouched."
        case .invalidData: "Saved alarm data could not be read safely. It has been left untouched."
        case .invalidDuration: "Choose a duration between one second and 99 hours, 59 minutes, 59 seconds."
        case .invalidTime: "Choose a valid hour and minute."
        }
    }
}

public enum AlarmScheduling {
    public static let maximumDuration = 99 * 3600 + 59 * 60 + 59
    public static func countdown(seconds: Int, now: Date = Date()) throws -> Date {
        guard (1...maximumDuration).contains(seconds) else { throw AlarmDataError.invalidDuration }
        return now.addingTimeInterval(TimeInterval(seconds))
    }
    public static func nextTime(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw AlarmDataError.invalidTime }
        guard let date = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                            matchingPolicy: .nextTime, repeatedTimePolicy: .first) else {
            throw AlarmDataError.invalidTime
        }
        return date
    }
}

public enum AlarmTimeWheel {
    public static func resolvedHour(previous: Int, selected: Int, use24Hour: Bool) -> Int {
        guard !use24Hour else { return selected }
        if previous % 12 == 11 && selected % 12 == 0 { return previous < 12 ? 12 : 0 }
        if previous % 12 == 0 && selected % 12 == 11 { return previous < 12 ? 23 : 11 }
        return selected // Direct AM/PM changes keep the same displayed hour.
    }
}

public enum RingtoneCatalog {
    public struct Tone: Identifiable, Sendable {
        public let id: String
        public let name: String
        public var filename: String { id + ".wav" }
    }
    public static let tones: [Tone] = [
        Tone(id: "classic-beep", name: "Classic Beep"), Tone(id: "digital-watch", name: "Digital Watch"),
        Tone(id: "soft-chime", name: "Soft Chime"), Tone(id: "xylophone", name: "Xylophone"),
        Tone(id: "sonar-ping", name: "Sonar Ping"), Tone(id: "church-bell", name: "Church Bell"),
        Tone(id: "rise-and-shine", name: "Rise & Shine"), Tone(id: "retro-arcade", name: "Retro Arcade"),
        Tone(id: "wind-bells", name: "Wind Bells"), Tone(id: "siren", name: "Siren")
    ]
}

public enum WakeTestOptions {
    public static let codeLengths = 4...10
    public static let typingTimes = 15...30
    public static let mathTimes = [5, 10, 15]
    public static let typingChoices = [15, 20, 25, 30]
    public static func nearest(_ value: Int, choices: [Int]) -> Int { choices.min { abs($0 - value) < abs($1 - value) } ?? value }
    public static func valid(codeLength: Int?, typingTime: Int?, mathTime: Int?) -> Bool {
        (codeLength.map { codeLengths.contains($0) } ?? true) &&
        (typingTime.map { typingTimes.contains($0) } ?? true) &&
        (mathTime.map { (5...12).contains($0) || $0 == 15 } ?? true)
    }
}

// Bounded, pre-scheduled alerts also survive a failed unlock or app termination.
// They are all owned by one visible alarm and cancelled together on entry/completion.
public enum AlarmRecovery {
    public static let offsets: [TimeInterval] = [20, 40, 60]
    public static func dates(after target: Date) -> [Date] { offsets.map { target.addingTimeInterval($0) } }
}

public enum AlarmRoutine {
    public static func validDays(_ days: [Int]?) -> Bool {
        guard let days else { return true }
        return Set(days).count == days.count && days.allSatisfy { (1...7).contains($0) }
    }
    public static func next(hour: Int, minute: Int, days: [Int], now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        guard validDays(days) else { throw AlarmDataError.invalidTime }
        if days.isEmpty { return try AlarmScheduling.nextTime(hour: hour, minute: minute, now: now, calendar: calendar) }
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw AlarmDataError.invalidTime }
        let dates = days.compactMap { calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: $0), matchingPolicy: .nextTime, repeatedTimePolicy: .first) }
        guard let date = dates.min() else { throw AlarmDataError.invalidTime }
        return date
    }
    public static func summary(_ days: [Int]) -> String {
        if days.count == 7 { return "Daily" }
        if days.isEmpty { return "Once" }
        if Set(days) == Set([2,3,4,5,6]) { return "Weekdays" }
        if Set(days) == Set([1,7]) { return "Weekends" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.sorted().map { names[$0 - 1] }.joined(separator: " · ")
    }
}
