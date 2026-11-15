import Foundation

public enum StroopColor: String, Codable, CaseIterable, Sendable {
    case red, blue, green, yellow
    public var name: String { rawValue.capitalized }
}

public struct StroopRound: Codable, Equatable, Sendable {
    public let word: StroopColor
    public let ink: StroopColor
    // Labels always use allCases order; their backgrounds deliberately disagree.
    public let buttonColors: [StroopColor]
    public var valid: Bool {
        word != ink && buttonColors.count == StroopColor.allCases.count &&
        Set(buttonColors).count == StroopColor.allCases.count &&
        zip(StroopColor.allCases, buttonColors).allSatisfy { $0 != $1 }
    }
    public static func create(previousInk: StroopColor? = nil, seed: UInt64? = nil) -> Self {
        var random = GameRandom(seed: seed ?? .random(in: .min ... .max))
        let colors = StroopColor.allCases
        let ink = colors.filter { $0 != previousInk }.randomElement(using: &random)!
        let word = colors.filter { $0 != ink }.randomElement(using: &random)!
        let offset = Int.random(in: 1..<colors.count, using: &random)
        return Self(word: word, ink: ink, buttonColors: colors.indices.map { colors[($0 + offset) % colors.count] })
    }
}
