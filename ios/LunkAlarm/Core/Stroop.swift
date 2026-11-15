import Foundation

public enum StroopColor: String, Codable, CaseIterable, Sendable {
    case red, blue, green, yellow
    public var name: String { rawValue.capitalized }
}

public struct StroopRound: Codable, Equatable, Sendable {
    public let word: StroopColor
    public let ink: StroopColor
    public let buttonColors: [StroopColor]
    public let choiceOrder: [StroopColor]?
    // Sessions from 1.9.0 retain their original layout until the next round.
    public var choices: [StroopColor] { choiceOrder ?? StroopColor.allCases }
    public var valid: Bool {
        word != ink && buttonColors.count == StroopColor.allCases.count &&
        Set(buttonColors).count == StroopColor.allCases.count &&
        choices.count == StroopColor.allCases.count && Set(choices) == Set(StroopColor.allCases) &&
        zip(choices, buttonColors).allSatisfy { $0 != $1 }
    }
    private static func orders(_ colors: [StroopColor]) -> [[StroopColor]] {
        if colors.isEmpty { return [[]] }
        return colors.flatMap { color in orders(colors.filter { $0 != color }).map { [color] + $0 } }
    }
    public static func create(previous: StroopRound? = nil, seed: UInt64? = nil) -> Self {
        var random = GameRandom(seed: seed ?? .random(in: .min ... .max))
        let colors = StroopColor.allCases
        let ink = colors.filter { $0 != previous?.ink }.randomElement(using: &random)!
        let word = colors.filter { $0 != ink }.randomElement(using: &random)!
        let candidates = orders(colors).filter { order in
            guard let previous else { return true }
            return zip(order, previous.choices).allSatisfy { $0 != $1 } &&
                order.firstIndex(of: ink) != previous.choices.firstIndex(of: previous.ink)
        }
        let choices = candidates.randomElement(using: &random)!
        let offset = Int.random(in: 1..<colors.count, using: &random)
        return Self(word: word, ink: ink, buttonColors: choices.indices.map { choices[($0 + offset) % choices.count] }, choiceOrder: choices)
    }
}
