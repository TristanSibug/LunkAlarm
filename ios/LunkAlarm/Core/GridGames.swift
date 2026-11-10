import Foundation

public struct GameRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct WakeGameOptions: Codable, Equatable, Sendable {
    public var puzzle = false
    public var puzzlePieces = 8
    public var puzzleSeconds = 30
    public var mines = false
    public var mineDifficulty = 0
    public var mineSeconds = 30
    public var sudoku = false
    public var sudokuDifficulty = 0
    public var sudokuSeconds = 120
    public var hasTests: Bool { puzzle || mines || sudoku }
    public init() {}
    public var valid: Bool {
        [6, 8, 10].contains(puzzlePieces) && Self.gameTimes.contains(puzzleSeconds) &&
        (0...2).contains(mineDifficulty) && Self.gameTimes.contains(mineSeconds) &&
        (0...3).contains(sudokuDifficulty) && Self.sudokuTimes.contains(sudokuSeconds)
    }
    public static let gameTimes = [15, 20, 25, 30, 35, 40]
    public static let sudokuTimes = [60, 120, 180, 240]
}

public struct MineBoard: Codable, Equatable, Sendable {
    public let size: Int
    public let mines: Set<Int>
    public private(set) var revealed: Set<Int>
    public private(set) var flags: Set<Int> = []
    public var cells: Range<Int> { 0..<(size * size) }
    public var complete: Bool { revealed.count == size * size - mines.count && flags == mines }
    public func neighbors(_ cell: Int) -> [Int] {
        (-1...1).flatMap { dy in (-1...1).compactMap { dx in
            let row = cell / size + dy, column = cell % size + dx
            return (dx != 0 || dy != 0) && (0..<size).contains(row) && (0..<size).contains(column) ? row * size + column : nil
        } }
    }
    public func number(_ cell: Int) -> Int { neighbors(cell).filter { mines.contains($0) }.count }
    public mutating func reveal(_ cell: Int) {
        guard cells.contains(cell), !flags.contains(cell), !mines.contains(cell) else { return }
        var pending = [cell]
        while let next = pending.popLast() {
            guard !flags.contains(next), !mines.contains(next), revealed.insert(next).inserted else { continue }
            if number(next) == 0 { pending.append(contentsOf: neighbors(next).filter { !revealed.contains($0) }) }
        }
    }
    public mutating func flag(_ cell: Int) {
        guard cells.contains(cell), !revealed.contains(cell) else { return }
        if !flags.insert(cell).inserted { flags.remove(cell) }
    }
    /// Standard chording: a revealed number opens its unflagged neighbors only
    /// when the adjacent flag count matches. Wrong flags can reveal a mine.
    public func chordTargets(_ cell: Int) -> [Int] {
        guard revealed.contains(cell), number(cell) > 0,
              neighbors(cell).filter({ flags.contains($0) }).count == number(cell) else { return [] }
        return neighbors(cell).filter { !revealed.contains($0) && !flags.contains($0) }
    }
    public func deductions() -> (safe: Set<Int>, mines: Set<Int>) {
        var safe = Set<Int>(), marked = Set<Int>()
        let hidden = Set(cells).subtracting(revealed).subtracting(flags)
        let left = mines.count - flags.count
        if left == 0 { safe.formUnion(hidden) }
        if left == hidden.count { marked.formUnion(hidden) }
        for cell in revealed {
            let near = neighbors(cell), unknown = Set(near).intersection(hidden)
            let remaining = number(cell) - near.filter { flags.contains($0) }.count
            if remaining == 0 { safe.formUnion(unknown) }
            if remaining == unknown.count { marked.formUnion(unknown) }
        }
        return (safe, marked)
    }
    public func solvableWithoutGuessing() -> Bool {
        var board = self; board.flags = []
        for _ in cells {
            if board.complete { return true }
            let before = board, deductions = board.deductions()
            board.flags.formUnion(deductions.mines)
            for cell in deductions.safe { board.reveal(cell) }
            if board == before { return false }
        }
        return board.complete
    }
    public var valid: Bool {
        [5, 7, 9].contains(size) && mines.count == [5: 4, 7: 8, 9: 14][size] &&
        mines.union(revealed).union(flags).allSatisfy(cells.contains) && revealed.isDisjoint(with: mines.union(flags))
    }
    public static func create(difficulty: Int, seed: UInt64 = .random(in: .min ... .max)) -> MineBoard {
        let level = min(2, max(0, difficulty)), size = [5, 7, 9][level], count = [4, 8, 14][level]
        var random = GameRandom(seed: seed)
        for _ in 0..<120 {
            var board = MineBoard(size: size, mines: Set((0..<(size * size)).shuffled(using: &random).prefix(count)), revealed: [])
            let openings = board.cells.filter { !board.mines.contains($0) && board.number($0) == 0 }
            guard let start = openings.randomElement(using: &random) else { continue }
            board.reveal(start)
            if board.solvableWithoutGuessing() { return board }
        }
        var fallback = MineBoard(size: size, mines: Set(0..<count), revealed: [])
        fallback.reveal(size * size - 1)
        return fallback
    }
}

public struct SudokuBoard: Codable, Equatable, Sendable {
    public let size: Int
    public let givens: [Int]
    public let solution: [Int]
    public private(set) var values: [Int]
    public var complete: Bool { values == solution }
    public var blanks: Int { givens.filter { $0 == 0 }.count }
    public var filled: Int { values.indices.filter { givens[$0] == 0 && values[$0] != 0 }.count }
    public mutating func enter(cell: Int, digit: Int) {
        guard values.indices.contains(cell), givens[cell] == 0, (0...size).contains(digit) else { return }
        values[cell] = digit
    }
    public func conflict(_ cell: Int) -> Bool {
        values[cell] != 0 && Self.peers(size: size, cell: cell).contains { values[$0] == values[cell] }
    }
    public var valid: Bool {
        guard [4, 6].contains(size), [givens, solution, values].allSatisfy({ $0.count == size * size }),
              givens.allSatisfy({ (0...size).contains($0) }), values.allSatisfy({ (0...size).contains($0) }),
              solution.allSatisfy({ (1...size).contains($0) }) else { return false }
        return values.indices.allSatisfy { i in
            (givens[i] == 0 || (givens[i] == solution[i] && values[i] == givens[i])) &&
            !Self.peers(size: size, cell: i).contains { solution[$0] == solution[i] }
        }
    }
    public static func peers(size: Int, cell: Int) -> [Int] {
        (0..<(size * size)).filter { p in p != cell && (p / size == cell / size || p % size == cell % size ||
            (p / size / 2 == cell / size / 2 && p % size / (size / 2) == cell % size / (size / 2))) }
    }
    public static func solutionCount(size: Int, input: [Int], limit: Int = 2) -> Int {
        guard [4, 6].contains(size), input.count == size * size, input.allSatisfy({ (0...size).contains($0) }),
              !input.indices.contains(where: { i in input[i] != 0 && peers(size: size, cell: i).contains { input[$0] == input[i] } }) else { return 0 }
        let neighbors = input.indices.map { peers(size: size, cell: $0) }
        var grid = input, found = 0
        func solve() {
            guard found < limit else { return }
            let empty = grid.indices.filter { grid[$0] == 0 }
            if empty.isEmpty { found += 1; return }
            let choices = empty.map { cell in (cell, (1...size).filter { digit in !neighbors[cell].contains { grid[$0] == digit } }) }
            let (cell, digits) = choices.min { $0.1.count < $1.1.count }!
            for digit in digits { grid[cell] = digit; solve(); if found >= limit { break } }
            grid[cell] = 0
        }
        solve(); return found
    }
    public static func create(difficulty: Int, seed: UInt64 = .random(in: .min ... .max)) -> SudokuBoard {
        let level = min(3, max(0, difficulty)), size = level < 2 ? 4 : 6
        var random = GameRandom(seed: seed)
        let rows = (0..<(size / 2)).shuffled(using: &random).flatMap { band in (0..<2).shuffled(using: &random).map { band * 2 + $0 } }
        let columns = (0..<2).shuffled(using: &random).flatMap { stack in (0..<(size / 2)).shuffled(using: &random).map { stack * (size / 2) + $0 } }
        let digits = (1...size).shuffled(using: &random)
        let solution = rows.flatMap { r in columns.map { c in digits[(r * (size / 2) + r / 2 + c) % size] } }
        var clues = solution, removed = 0
        for cell in clues.indices.shuffled(using: &random) {
            let old = clues[cell]; clues[cell] = 0
            if solutionCount(size: size, input: clues) != 1 { clues[cell] = old } else { removed += 1 }
            if removed == [6, 10, 14, 22][level] { break }
        }
        return SudokuBoard(size: size, givens: clues, solution: solution, values: clues)
    }
}
