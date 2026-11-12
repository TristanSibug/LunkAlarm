import Foundation

public enum MathOperation: String, Codable, CaseIterable, Sendable {
    case addition, subtraction, multiplication, division
    public var symbol: String { switch self { case .addition: "+"; case .subtraction: "−"; case .multiplication: "×"; case .division: "÷" } }
}

public struct WakeChallenge: Codable, Equatable, Sendable {
    public enum DigitResult: Equatable, Sendable { case incomplete, incorrect, correct, timedOut }
    public let code: String
    public private(set) var typingPending: Bool
    public private(set) var remaining: Int
    public private(set) var left: Int
    public private(set) var right: Int
    public var complete: Bool { !typingPending && remaining == 0 }
    public private(set) var operation: MathOperation?
    private var operations: [MathOperation]?
    public var answer: Int { switch operation ?? .addition { case .addition: left + right; case .subtraction: left - right; case .multiplication: left * right; case .division: left / max(1, right) } }
    public var answerDigitCount: Int { String(answer).count }
    public init(typing: Bool, mathCount: Int, codeLength: Int = 8, operations: [MathOperation] = [.addition]) {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789")
        code = String((0..<min(10, max(4, codeLength))).map { _ in alphabet.randomElement()! })
        typingPending = typing
        remaining = min(8, max(0, mathCount))
        self.operations = operations.isEmpty ? [.addition] : operations
        left = 1; right = 1; nextProblem()
    }
    @discardableResult public mutating func submit(code attempt: String) -> Bool {
        guard typingPending, attempt == code else { return false }
        typingPending = false
        return true
    }
    @discardableResult public mutating func submit(answer: Int) -> Bool {
        guard !typingPending, remaining > 0, answer == self.answer else { return false }
        remaining -= 1
        if remaining > 0 { nextProblem() }
        return true
    }
    private mutating func nextProblem() {
        operation = (operations ?? [.addition]).randomElement() ?? .addition
        left = Int.random(in: 1...20); right = Int.random(in: 1...20)
        switch operation! {
        case .addition: break
        case .subtraction: if left < right { swap(&left, &right) }
        case .multiplication: left = Int.random(in: 1...12); right = Int.random(in: 1...12)
        case .division: right = Int.random(in: 1...12); left = right * Int.random(in: 1...12)
        }
    }
    public mutating func submit(digits: String) -> DigitResult {
        guard !typingPending, remaining > 0, digits.count >= answerDigitCount else { return .incomplete }
        guard digits == String(answer) else { return .incorrect }
        _ = submit(answer: answer)
        return .correct
    }
}
