import Foundation

public struct WakeChallenge: Sendable {
    public let code: String
    public private(set) var typingPending: Bool
    public private(set) var remaining: Int
    public private(set) var left: Int
    public private(set) var right: Int
    public var complete: Bool { !typingPending && remaining == 0 }
    public init(typing: Bool, mathCount: Int) {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789")
        code = String((0..<8).map { _ in alphabet.randomElement()! })
        typingPending = typing
        remaining = min(8, max(0, mathCount))
        left = Int.random(in: 1...20); right = Int.random(in: 1...20)
    }
    @discardableResult public mutating func submit(code attempt: String) -> Bool {
        guard typingPending, attempt == code else { return false }
        typingPending = false
        return true
    }
    @discardableResult public mutating func submit(answer: Int) -> Bool {
        guard !typingPending, remaining > 0, answer == left + right else { return false }
        remaining -= 1
        if remaining > 0 { left = Int.random(in: 1...20); right = Int.random(in: 1...20) }
        return true
    }
}
