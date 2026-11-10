import Foundation

public struct PuzzlePoint: Codable, Equatable, Sendable { public let x: Int; public let y: Int }
public struct PuzzleEdge: Codable, Equatable, Sendable { public let from: PuzzlePoint; public let to: PuzzlePoint; public let tab: Double; public let center: Double }
public struct PuzzlePiece: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let edges: [PuzzleEdge]
    public var x: Int { edges.map { min($0.from.x, $0.to.x) }.min()! }
    public var y: Int { edges.map { min($0.from.y, $0.to.y) }.min()! }
}
public struct Jigsaw: Equatable, Sendable {
    public let columns: Int
    public let pieces: [PuzzlePiece]
    public let order: [Int]
    public static func create(count: Int, seed: UInt64) -> Jigsaw {
        let count = [6, 8, 10].contains(count) ? count : 8, columns = count / 2
        var random = GameRandom(seed: seed), seams: [String: (Double, Double)] = [:]
        func owner(_ x: Int, _ y: Int) -> Int? { (0..<columns).contains(x) && (0..<2).contains(y) ? y * columns + x : nil }
        let pieces = (0..<count).map { id in
            let x = id % columns, y = id / columns
            let corners = [PuzzlePoint(x: x, y: y), PuzzlePoint(x: x + 1, y: y), PuzzlePoint(x: x + 1, y: y + 1), PuzzlePoint(x: x, y: y + 1)]
            let neighbors = [owner(x, y - 1), owner(x + 1, y), owner(x, y + 1), owner(x - 1, y)]
            let edges = (0..<4).map { side in
                let a = corners[side], b = corners[(side + 1) % 4], forward = a.x < b.x || a.y < b.y
                let first = forward ? a : b, last = forward ? b : a
                let key = "\(first.x),\(first.y)-\(last.x),\(last.y)"
                var seam = (0.0, 0.5)
                if neighbors[side] != nil {
                    if let existing = seams[key] { seam = existing }
                    else { seam = ((Bool.random(using: &random) ? 1 : -1) * Double.random(in: 0.16...0.23, using: &random), Double.random(in: 0.43...0.57, using: &random)); seams[key] = seam }
                }
                return PuzzleEdge(from: a, to: b, tab: forward ? seam.0 : -seam.0, center: forward ? seam.1 : 1 - seam.1)
            }
            return PuzzlePiece(id: id, edges: edges)
        }
        return Jigsaw(columns: columns, pieces: pieces, order: (0..<count).shuffled(using: &random))
    }
}
