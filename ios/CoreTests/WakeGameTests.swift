import Foundation
import XCTest
@testable import LunkAlarmCore

final class WakeGameTests: XCTestCase {
    func testAllMineDifficultiesHaveExactSizeAndCanBeSolvedWithoutGuessing() {
        for level in 0...2 { for seed in UInt64(0)...60 {
            var board = MineBoard.create(difficulty: level, seed: seed)
            XCTAssertEqual(board.size, [5, 7, 9][level]); XCTAssertEqual(board.mines.count, [4, 8, 14][level])
            XCTAssertTrue(board.valid); XCTAssertTrue(board.solvableWithoutGuessing()); XCTAssertFalse(board.complete)
            XCTAssertFalse(board.revealed.isEmpty); XCTAssertTrue(board.revealed.isDisjoint(with: board.mines))
            for _ in board.cells {
                let d = board.deductions()
                for cell in d.mines where !board.flags.contains(cell) { board.flag(cell) }
                for cell in d.safe { board.reveal(cell) }
            }
            XCTAssertTrue(board.complete)
        } }
    }
    func testChordRequiresMatchingFlagsAndOnlyReturnsUnflaggedHiddenNeighbors() {
        var board = MineBoard(size: 5, mines: [0, 4, 20, 24], revealed: [6])
        XCTAssertEqual(board.number(6), 1); XCTAssertTrue(board.chordTargets(6).isEmpty)
        board.flag(0)
        XCTAssertEqual(Set(board.chordTargets(6)), Set([1, 2, 5, 7, 10, 11, 12]))
        for target in board.chordTargets(6) { board.reveal(target) }
        XCTAssertTrue(board.revealed.contains(7)); XCTAssertFalse(board.revealed.contains(0))
        XCTAssertTrue(board.chordTargets(0).isEmpty)
        board.flag(0); XCTAssertFalse(board.flags.contains(0))
    }
    func testMineChordFlowsThroughTimedChallengeWithoutExtendingDeadline() throws {
        var options = WakeGameOptions(); options.mines = true; options.mineSeconds = 40
        let start = Date(timeIntervalSince1970: 1000)
        let base = TimedWakeChallenge(typing: false, mathCount: 0, games: options, now: start)
        // A controlled valid board exercises a successful chord and incorrect-flag failure.
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        let board = MineBoard(size: 5, mines: [0, 4, 20, 24], revealed: [6])
        payload["mineBoard"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(board))
        var c = try JSONDecoder().decode(TimedWakeChallenge.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertTrue(c.valid)
        _ = c.mineAction(cell: 0, flag: true, now: start.addingTimeInterval(1))
        let deadline = c.deadline
        XCTAssertEqual(c.mineAction(cell: 6, chord: true, now: start.addingTimeInterval(2)), .correct)
        XCTAssertTrue(c.mineBoard!.revealed.contains(7)); XCTAssertEqual(c.deadline, deadline)
        var wrong = try JSONDecoder().decode(TimedWakeChallenge.self, from: JSONSerialization.data(withJSONObject: payload))
        _ = wrong.mineAction(cell: 1, flag: true, now: start.addingTimeInterval(1))
        XCTAssertEqual(wrong.mineAction(cell: 6, chord: true, now: start.addingTimeInterval(2)), .incorrect)
        XCTAssertEqual(wrong.resetCount, 1)
    }
    func testSudokuDifficultiesHaveUniqueSolutionsAndReversibleEntries() {
        for level in 0...3 { for seed in UInt64(0)...18 {
            var board = SudokuBoard.create(difficulty: level, seed: seed)
            XCTAssertTrue(board.valid); XCTAssertEqual(board.size, level < 2 ? 4 : 6)
            XCTAssertEqual(SudokuBoard.solutionCount(size: board.size, input: board.givens), 1)
            XCTAssertFalse(board.complete); XCTAssertGreaterThan(board.blanks, 0)
            let empty = board.givens.firstIndex(of: 0)!, fixed = board.givens.firstIndex(where: { $0 != 0 })!
            board.enter(cell: fixed, digit: 0); XCTAssertEqual(board.values[fixed], board.givens[fixed])
            board.enter(cell: empty, digit: board.solution[empty]); XCTAssertEqual(board.filled, 1)
            board.enter(cell: empty, digit: 0); XCTAssertEqual(board.filled, 0)
            for cell in board.values.indices { board.enter(cell: cell, digit: board.solution[cell]) }
            XCTAssertTrue(board.complete)
        } }
    }
    func testJigsawHasOnlyEvenPieceCountsWithComplementarySeamsAndOnePositionEach() {
        for count in [6, 8, 10] { for seed in UInt64(0)...30 {
            let puzzle = Jigsaw.create(count: count, seed: seed)
            XCTAssertEqual(puzzle.pieces.count, count); XCTAssertEqual(Set(puzzle.order), Set(0..<count))
            XCTAssertEqual(Set(puzzle.pieces.map { "\($0.x),\($0.y)" }).count, count)
            let edges = puzzle.pieces.flatMap(\.edges)
            for edge in edges where edge.tab != 0 {
                let other = edges.first { $0.from == edge.to && $0.to == edge.from }!
                XCTAssertEqual(edge.tab, -other.tab, accuracy: 0.00001); XCTAssertEqual(edge.center, 1 - other.center, accuracy: 0.00001)
            }
        } }
    }
    func testAllFiveStagesKeepGameDeadlinesAndRestartEverythingOnTimeout() {
        let start = Date(timeIntervalSince1970: 1000)
        var options = WakeGameOptions(); options.puzzle = true; options.mines = true; options.sudoku = true; options.sudokuSeconds = 240
        var c = TimedWakeChallenge(typing: true, mathCount: 1, games: options, now: start)
        XCTAssertEqual(c.phase, .typing)
        XCTAssertEqual(c.placePiece(0, now: start), .incomplete)
        _ = c.submit(code: c.code, now: start.addingTimeInterval(1)); XCTAssertEqual(c.phase, .math)
        _ = c.submit(digits: "\(c.left + c.right)", now: start.addingTimeInterval(2)); XCTAssertEqual(c.phase, .puzzle)
        for piece in 0..<8 { _ = c.placePiece(piece, now: start.addingTimeInterval(3)) }
        XCTAssertEqual(c.phase, .mines); let mineDeadline = c.deadline
        for cell in c.mineBoard!.cells {
            let board = c.mineBoard!
            _ = c.mineAction(cell: cell, flag: board.mines.contains(cell), now: start.addingTimeInterval(4))
            if c.minesPending { XCTAssertEqual(c.deadline, mineDeadline) }
        }
        XCTAssertEqual(c.phase, .sudoku); XCTAssertEqual(c.deadline, start.addingTimeInterval(244))
        let board = c.sudokuBoard!
        for cell in board.givens.indices where board.givens[cell] == 0 { _ = c.sudokuAction(cell: cell, digit: board.solution[cell], now: start.addingTimeInterval(5)) }
        XCTAssertTrue(c.complete); XCTAssertNil(c.deadline)
        var expired = TimedWakeChallenge(typing: true, mathCount: 1, games: options, now: start)
        _ = expired.submit(code: expired.code, now: start.addingTimeInterval(1))
        _ = expired.submit(digits: "\(expired.left + expired.right)", now: start.addingTimeInterval(2))
        let deadline = expired.deadline!
        XCTAssertEqual(expired.placePiece(0, now: deadline), .timedOut)
        XCTAssertEqual(expired.phase, .typing); XCTAssertEqual(expired.answered, 0); XCTAssertEqual(expired.resetCount, 1)
    }
    func testSavedGameProgressAndVibrationSnapshotsRoundTripAndLegacyDataStillLoads() throws {
        var games = WakeGameOptions(); games.mines = true; games.sudoku = true
        var state = SavedState(); state.settings.wakeGames = games; state.settings.vibrateInApp = true
        var record = AlarmRecord(target: Date(), isTimer: false, ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: false, mathCount: 0, status: .needsChallenge)
        record.wakeGames = games; record.vibrateInApp = true
        var c = TimedWakeChallenge(typing: false, mathCount: 0, games: games)
        _ = c.mineAction(cell: c.mineBoard!.mines.first!, flag: true)
        state.alarms = [record]; state.challengeSession = SavedChallengeSession(owner: record.id, challenge: c)
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: encoded).validated(), state)
        let duplicate = try record.duplicated(); XCTAssertEqual(duplicate.wakeGames, games); XCTAssertEqual(duplicate.vibrateInApp, true)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedState())) as! [String: Any]
        var settings = old["settings"] as! [String: Any]
        for key in ["wakeGames", "nativeMathKeyboard", "vibrateInApp"] { settings.removeValue(forKey: key) }; old["settings"] = settings
        XCTAssertNil(try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: old)).validated().settings.wakeGames)
        state.challengeSession!.owner = UUID(); XCTAssertThrowsError(try state.validated())
    }
    func testOptionsHaveNewSudokuTimersAndRejectInvalidBoards() {
        XCTAssertEqual(WakeGameOptions.sudokuTimes, [60, 120, 180, 240])
        for time in WakeGameOptions.sudokuTimes { var g = WakeGameOptions(); g.sudokuSeconds = time; XCTAssertTrue(g.valid) }
        var g = WakeGameOptions(); g.puzzlePieces = 7; XCTAssertFalse(g.valid)
        g = .init(); g.sudokuSeconds = 30; XCTAssertFalse(g.valid)
        XCTAssertFalse(MineBoard(size: 5, mines: [99], revealed: []).valid)
    }
}
