import XCTest
@testable import LunkAlarmCore

final class StroopTests: XCTestCase {
    func testWordsAndButtonColorsConflictWhileAnswerPositionsStayFixed() {
        var previous: StroopColor?
        for seed in UInt64(0)..<500 {
            let round = StroopRound.create(previousInk: previous, seed: seed)
            XCTAssertTrue(round.valid)
            XCTAssertNotEqual(round.ink, round.word)
            XCTAssertNotEqual(round.ink, previous)
            XCTAssertEqual(Set(round.buttonColors), Set(StroopColor.allCases))
            for (label, background) in zip(StroopColor.allCases, round.buttonColors) { XCTAssertNotEqual(label, background) }
            previous = round.ink
        }
        XCTAssertEqual(StroopColor.allCases.map(\.name), ["Red", "Blue", "Green", "Yellow"])
    }
    func testSettingsBoundsAndDefaults() {
        XCTAssertFalse(WakeGameOptions().hasTests)
        XCTAssertEqual(WakeGameOptions().stroopRoundCount, 5)
        XCTAssertEqual(WakeGameOptions().stroopTimeLimit, 5)
        XCTAssertEqual(WakeGameOptions.stroopRoundChoices, Array(3...8))
        XCTAssertEqual(WakeGameOptions.stroopTimes, [3, 4, 5, 6])
        for rounds in 3...8 { for seconds in 3...6 {
            var games = WakeGameOptions(); games.stroop = true; games.stroopRoundCount = rounds; games.stroopTimeLimit = seconds
            XCTAssertTrue(games.hasTests); XCTAssertTrue(games.valid)
        } }
        for rounds in [2, 9] { var games = WakeGameOptions(); games.stroopRounds = rounds; XCTAssertFalse(games.valid) }
        for seconds in [2, 7] { var games = WakeGameOptions(); games.stroopSeconds = seconds; XCTAssertFalse(games.valid) }
    }
    func testCorrectAnswersAdvanceAndRenewEachRoundButWrongAnswersDoNot() {
        let start = Date(timeIntervalSince1970: 1000)
        for rounds in 3...8 {
            var games = WakeGameOptions(); games.stroop = true; games.stroopRounds = rounds; games.stroopSeconds = 6
            var challenge = TimedWakeChallenge(typing: false, mathCount: 0, games: games, now: start, seed: 123)
            XCTAssertEqual(challenge.phase, .stroop); XCTAssertEqual(challenge.deadline, start.addingTimeInterval(6))
            for i in 0..<rounds {
                let round = challenge.stroopRound!, deadline = challenge.deadline
                let now = start.addingTimeInterval(Double(i + 1) / 2)
                XCTAssertEqual(challenge.submit(stroop: round.word, now: now), .incorrect)
                XCTAssertEqual(challenge.stroopAnswered, i); XCTAssertEqual(challenge.deadline, deadline)
                XCTAssertEqual(challenge.submit(stroop: round.ink, now: now), .correct)
                XCTAssertEqual(challenge.stroopAnswered, i + 1); XCTAssertTrue(challenge.valid)
                if i + 1 < rounds {
                    XCTAssertEqual(challenge.deadline, now.addingTimeInterval(6))
                    XCTAssertNotEqual(challenge.stroopRound!.ink, round.ink)
                }
            }
            XCTAssertTrue(challenge.complete); XCTAssertNil(challenge.deadline)
            XCTAssertEqual(challenge.submit(stroop: .red, now: start.addingTimeInterval(5)), .incomplete)
        }
    }
    func testTimeoutAndLateAnswersRestartTheEntireSequence() {
        let start = Date(timeIntervalSince1970: 1000)
        var games = WakeGameOptions(); games.stroop = true; games.stroopRounds = 3; games.stroopSeconds = 3
        var c = TimedWakeChallenge(typing: true, mathCount: 1, games: games, now: start)
        let firstDeadline = c.deadline
        XCTAssertEqual(c.submit(stroop: c.stroopRound!.ink, now: start), .incomplete)
        XCTAssertEqual(c.deadline, firstDeadline)
        XCTAssertTrue(c.submit(code: c.code, now: start.addingTimeInterval(1)))
        XCTAssertEqual(c.submit(digits: String(c.left + c.right), now: start.addingTimeInterval(2)), .correct)
        XCTAssertEqual(c.phase, .stroop)
        XCTAssertEqual(c.submit(stroop: c.stroopRound!.ink, now: start.addingTimeInterval(3)), .correct)
        XCTAssertEqual(c.stroopAnswered, 1)
        XCTAssertEqual(c.submit(stroop: c.stroopRound!.ink, now: c.deadline!), .timedOut)
        XCTAssertEqual(c.phase, .typing); XCTAssertEqual(c.answered, 0); XCTAssertEqual(c.stroopAnswered, 0)
        XCTAssertEqual(c.resetCount, 1); XCTAssertTrue(c.valid)
        var onlyStroop = TimedWakeChallenge(typing: false, mathCount: 0, games: games, now: start)
        XCTAssertTrue(onlyStroop.expireIfNeeded(now: start.addingTimeInterval(3)))
        XCTAssertEqual(onlyStroop.phase, .stroop); XCTAssertEqual(onlyStroop.stroopAnswered, 0)
        XCTAssertEqual(onlyStroop.deadline, start.addingTimeInterval(6))
    }
    func testAllSixStagesReachStroopBeforeCompleting() {
        let now = Date(timeIntervalSince1970: 1000)
        var games = WakeGameOptions(); games.puzzle = true; games.mines = true; games.sudoku = true; games.stroop = true; games.stroopRounds = 3
        var c = TimedWakeChallenge(typing: true, mathCount: 1, games: games, now: now, seed: 24)
        _ = c.submit(code: c.code, now: now)
        _ = c.submit(digits: String(c.left + c.right), now: now)
        XCTAssertEqual(c.phase, .puzzle)
        for piece in 0..<games.puzzlePieces { _ = c.placePiece(piece, now: now) }
        XCTAssertEqual(c.phase, .mines)
        for mine in c.mineBoard!.mines { _ = c.mineAction(cell: mine, flag: true, now: now) }
        _ = c.mineAction(cell: -1, now: now)
        XCTAssertEqual(c.phase, .sudoku)
        let board = c.sudokuBoard!
        for cell in board.givens.indices where board.givens[cell] == 0 { _ = c.sudokuAction(cell: cell, digit: board.solution[cell], now: now) }
        XCTAssertEqual(c.phase, .stroop); XCTAssertFalse(c.complete)
        for _ in 0..<3 { _ = c.submit(stroop: c.stroopRound!.ink, now: now) }
        XCTAssertTrue(c.complete); XCTAssertNil(c.deadline)
    }
    func testSettingsProgressDuplicatesAndDeadlinesRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var games = WakeGameOptions(); games.stroop = true; games.stroopRounds = 8; games.stroopSeconds = 4
        var alarm = AlarmRecord(target: now, isTimer: false, ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: false, mathCount: 0, status: .needsChallenge)
        alarm.wakeGames = games; XCTAssertTrue(alarm.hasTests)
        var c = TimedWakeChallenge(typing: false, mathCount: 0, games: games, now: now)
        _ = c.submit(stroop: c.stroopRound!.ink, now: now.addingTimeInterval(1))
        var state = SavedState(); state.settings.wakeGames = games; state.alarms = [alarm]
        state.challengeSession = SavedChallengeSession(owner: alarm.id, challenge: c)
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)).validated()
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.challengeSession!.challenge.stroopAnswered, 1)
        XCTAssertEqual(restored.challengeSession!.challenge.deadline, now.addingTimeInterval(5))
        let duplicate = try alarm.duplicated(now: now)
        XCTAssertNotEqual(duplicate.id, alarm.id); XCTAssertEqual(duplicate.wakeGames, games); XCTAssertTrue(duplicate.hasTests)
    }
    func testLegacyGameSettingsAndActiveSessionsDecodeWithoutEnablingStroop() throws {
        var games = WakeGameOptions(); games.puzzle = true
        var alarm = AlarmRecord(target: Date(), isTimer: true, ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: false, mathCount: 0)
        alarm.wakeGames = games
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TimedWakeChallenge(typing: false, mathCount: 0, games: games))) as! [String: Any]
        old.removeValue(forKey: "stroopRound"); old.removeValue(forKey: "stroopProgress")
        var oldGames = old["games"] as! [String: Any]
        for key in ["stroop", "stroopRounds", "stroopSeconds"] { oldGames.removeValue(forKey: key) }; old["games"] = oldGames
        let decoded = try JSONDecoder().decode(TimedWakeChallenge.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.valid); XCTAssertEqual(decoded.phase, .puzzle)
        XCTAssertFalse(decoded.stroopPending); XCTAssertEqual(decoded.stroopAnswered, 0)
        var state = SavedState(); state.alarms = [alarm]; state.challengeSession = SavedChallengeSession(owner: alarm.id, challenge: decoded)
        XCTAssertNoThrow(try state.validated())
    }
    func testCorruptStroopProgressAndRoundsAreRejected() throws {
        var games = WakeGameOptions(); games.stroop = true
        let c = TimedWakeChallenge(typing: false, mathCount: 0, games: games)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        payload["stroopProgress"] = 9
        XCTAssertFalse(try JSONDecoder().decode(TimedWakeChallenge.self, from: JSONSerialization.data(withJSONObject: payload)).valid)
        payload["stroopProgress"] = 0
        var round = payload["stroopRound"] as! [String: Any]; round["word"] = round["ink"]; payload["stroopRound"] = round
        XCTAssertFalse(try JSONDecoder().decode(TimedWakeChallenge.self, from: JSONSerialization.data(withJSONObject: payload)).valid)
    }
}
