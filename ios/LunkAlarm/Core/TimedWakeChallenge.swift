import Foundation

public struct TimedWakeChallenge: Sendable {
    private let typing: Bool
    private let mathCount: Int
    public let codeLength: Int
    public let typingTimeLimit: Int
    public let mathTimeLimit: Int
    private var challenge: WakeChallenge
    public private(set) var deadline: Date?
    public private(set) var resetCount = 0
    public var code: String { challenge.code }
    public var typingPending: Bool { challenge.typingPending }
    public var remaining: Int { challenge.remaining }
    public var left: Int { challenge.left }
    public var right: Int { challenge.right }
    public var complete: Bool { challenge.complete }
    public var answered: Int { mathCount - remaining }

    public init(typing: Bool, mathCount: Int, codeLength: Int = 8, typingTimeLimit: Int = 30, mathTimeLimit: Int = 10, now: Date = Date()) {
        self.codeLength = min(10, max(4, codeLength))
        self.typingTimeLimit = min(30, max(15, typingTimeLimit))
        self.mathTimeLimit = min(12, max(5, mathTimeLimit))
        self.typing = typing
        self.mathCount = min(8, max(0, mathCount))
        challenge = WakeChallenge(typing: typing, mathCount: mathCount, codeLength: self.codeLength)
        renewDeadline(now: now)
    }
    public func secondsRemaining(now: Date = Date()) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }
    @discardableResult public mutating func expireIfNeeded(now: Date = Date()) -> Bool {
        guard !complete, let deadline, now >= deadline else { return false }
        challenge = WakeChallenge(typing: typing, mathCount: mathCount, codeLength: self.codeLength)
        resetCount += 1
        renewDeadline(now: now)
        return true
    }
    public mutating func submit(code: String, now: Date = Date()) -> Bool {
        guard !expireIfNeeded(now: now), challenge.submit(code: code) else { return false }
        renewDeadline(now: now)
        return true
    }
    public mutating func submit(digits: String, now: Date = Date()) -> WakeChallenge.DigitResult {
        if expireIfNeeded(now: now) { return .timedOut }
        let result = challenge.submit(digits: digits)
        if result == .correct { renewDeadline(now: now) }
        return result
    }
    private mutating func renewDeadline(now: Date) {
        deadline = complete ? nil : now.addingTimeInterval(TimeInterval(typingPending ? typingTimeLimit : mathTimeLimit))
    }
}

public enum AlarmSoundLevel {
    public static let fadeDuration: TimeInterval = 10
    public static func gain(level: Double, elapsed: TimeInterval, gradual: Bool) -> Double {
        min(1, max(0, level)) * (gradual ? min(1, max(0, elapsed) / fadeDuration) : 1)
    }
}
