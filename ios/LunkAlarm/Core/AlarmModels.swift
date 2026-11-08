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
    public var hasTests: Bool { typing || mathCount > 0 }
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
    public init() {}

    public func validated() throws -> SavedState {
        guard version == 1 else { throw AlarmDataError.unsupportedVersion }
        guard Set(alarms.map(\.id)).count == alarms.count,
              Set(importedSounds.map(\.id)).count == importedSounds.count,
              (0...8).contains(settings.mathCount), (0...23).contains(settings.hour),
              (0...59).contains(settings.minute),
              settings.soundLevel.map({ (0.1...1).contains($0) }) ?? true,
              (0...AlarmScheduling.maximumDuration).contains(settings.durationSeconds),
              alarms.allSatisfy({ (0...8).contains($0.mathCount) && Self.safeFilename($0.soundFilename) }),
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
