import Foundation

public enum WakePhase: String, Codable, Sendable { case typing, math, puzzle, mines, sudoku, complete }

public struct TimedWakeChallenge: Codable, Equatable, Sendable {
    private let typing: Bool
    private let mathCount: Int
    public let codeLength: Int
    public let typingTimeLimit: Int
    public let mathTimeLimit: Int
    public let games: WakeGameOptions
    private var challenge: WakeChallenge
    public private(set) var deadline: Date?
    public private(set) var resetCount = 0
    public private(set) var puzzleSeed: UInt64
    public private(set) var placedPieces: Set<Int> = []
    public private(set) var mineBoard: MineBoard?
    public private(set) var sudokuBoard: SudokuBoard?
    public var code: String { challenge.code }
    public var typingPending: Bool { challenge.typingPending }
    public var remaining: Int { challenge.remaining }
    public var left: Int { challenge.left }
    public var right: Int { challenge.right }
    public var puzzlePending: Bool { games.puzzle && placedPieces.count < games.puzzlePieces }
    public var minesPending: Bool { games.mines && mineBoard?.complete != true }
    public var sudokuPending: Bool { games.sudoku && sudokuBoard?.complete != true }
    public var phase: WakePhase {
        if typingPending { return .typing }; if remaining > 0 { return .math }; if puzzlePending { return .puzzle }
        if minesPending { return .mines }; if sudokuPending { return .sudoku }; return .complete
    }
    public var complete: Bool { phase == .complete }
    public var answered: Int { mathCount - remaining }
    public var valid: Bool {
        games.valid && (4...10).contains(codeLength) && code.count == codeLength && (0...8).contains(mathCount) &&
        (0...mathCount).contains(remaining) && (1...20).contains(left) && (1...20).contains(right) &&
        WakeTestOptions.valid(codeLength: codeLength, typingTime: typingTimeLimit, mathTime: mathTimeLimit) &&
        placedPieces.allSatisfy({ (0..<games.puzzlePieces).contains($0) }) &&
        (!games.mines || (mineBoard?.valid == true && mineBoard?.size == [5, 7, 9][games.mineDifficulty])) &&
        (!games.sudoku || (sudokuBoard?.valid == true && sudokuBoard?.size == (games.sudokuDifficulty < 2 ? 4 : 6)))
    }
    public init(typing: Bool, mathCount: Int, codeLength: Int = 8, typingTimeLimit: Int = 30, mathTimeLimit: Int = 10, games: WakeGameOptions = .init(), now: Date = Date(), seed: UInt64? = nil) {
        self.codeLength = min(10, max(4, codeLength)); self.typingTimeLimit = min(30, max(15, typingTimeLimit))
        self.mathTimeLimit = min(15, max(5, mathTimeLimit)); self.typing = typing; self.mathCount = min(8, max(0, mathCount))
        self.games = games.valid ? games : .init()
        challenge = WakeChallenge(typing: typing, mathCount: mathCount, codeLength: self.codeLength)
        puzzleSeed = seed ?? .random(in: .min ... .max)
        mineBoard = self.games.mines ? MineBoard.create(difficulty: self.games.mineDifficulty, seed: seed ?? .random(in: .min ... .max)) : nil
        sudokuBoard = self.games.sudoku ? SudokuBoard.create(difficulty: self.games.sudokuDifficulty, seed: seed.map { $0 &+ 1 } ?? .random(in: .min ... .max)) : nil
        renewDeadline(now: now)
    }
    public func secondsRemaining(now: Date = Date()) -> Int {
        guard let deadline else { return 0 }; return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }
    private mutating func restart(now: Date) {
        challenge = WakeChallenge(typing: typing, mathCount: mathCount, codeLength: codeLength)
        placedPieces = []; puzzleSeed = .random(in: .min ... .max)
        mineBoard = games.mines ? MineBoard.create(difficulty: games.mineDifficulty) : nil
        sudokuBoard = games.sudoku ? SudokuBoard.create(difficulty: games.sudokuDifficulty) : nil
        resetCount += 1; renewDeadline(now: now)
    }
    @discardableResult public mutating func expireIfNeeded(now: Date = Date()) -> Bool {
        guard !complete, let deadline, now >= deadline else { return false }
        restart(now: now); return true
    }
    public mutating func submit(code: String, now: Date = Date()) -> Bool {
        guard !expireIfNeeded(now: now), challenge.submit(code: code) else { return false }
        renewDeadline(now: now); return true
    }
    public mutating func submit(digits: String, now: Date = Date()) -> WakeChallenge.DigitResult {
        if expireIfNeeded(now: now) { return .timedOut }
        let result = challenge.submit(digits: digits)
        if result == .correct { renewDeadline(now: now) }; return result
    }
    public mutating func placePiece(_ piece: Int, now: Date = Date()) -> WakeChallenge.DigitResult {
        if expireIfNeeded(now: now) { return .timedOut }
        guard phase == .puzzle, (0..<games.puzzlePieces).contains(piece), placedPieces.insert(piece).inserted else { return .incomplete }
        if !puzzlePending { renewDeadline(now: now) }; return .correct
    }
    public mutating func mineAction(cell: Int, flag: Bool = false, chord: Bool = false, now: Date = Date()) -> WakeChallenge.DigitResult {
        if expireIfNeeded(now: now) { return .timedOut }
        guard phase == .mines, var board = mineBoard, board.cells.contains(cell) else { return .incomplete }
        if chord {
            let targets = board.chordTargets(cell)
            if targets.contains(where: { board.mines.contains($0) }) { restart(now: now); return .incorrect }
            for target in targets { board.reveal(target) }
        } else if flag { board.flag(cell) }
        else if !board.flags.contains(cell) {
            if board.mines.contains(cell) { restart(now: now); return .incorrect }; board.reveal(cell)
        }
        mineBoard = board
        if board.complete { renewDeadline(now: now) }; return .correct
    }
    public mutating func sudokuAction(cell: Int, digit: Int, now: Date = Date()) -> WakeChallenge.DigitResult {
        if expireIfNeeded(now: now) { return .timedOut }
        guard phase == .sudoku, var board = sudokuBoard else { return .incomplete }
        board.enter(cell: cell, digit: digit); sudokuBoard = board
        if board.complete { renewDeadline(now: now) }; return .correct
    }
    private mutating func renewDeadline(now: Date) {
        let seconds: Int = switch phase {
        case .typing: typingTimeLimit; case .math: mathTimeLimit; case .puzzle: games.puzzleSeconds
        case .mines: games.mineSeconds; case .sudoku: games.sudokuSeconds; case .complete: 0
        }
        deadline = complete ? nil : now.addingTimeInterval(TimeInterval(seconds))
    }
}

public struct SavedChallengeSession: Codable, Equatable, Sendable {
    public var owner: UUID
    public var challenge: TimedWakeChallenge
    public init(owner: UUID, challenge: TimedWakeChallenge) { self.owner = owner; self.challenge = challenge }
}

public enum AlarmSoundLevel {
    public static let fadeDuration: TimeInterval = 10
    public static func gain(level: Double, elapsed: TimeInterval, gradual: Bool) -> Double {
        min(1, max(0, level)) * (gradual ? min(1, max(0, elapsed) / fadeDuration) : 1)
    }
}
