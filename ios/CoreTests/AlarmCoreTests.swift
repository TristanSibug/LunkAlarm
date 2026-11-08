import Foundation
import XCTest
@testable import LunkAlarmCore

final class AlarmCoreTests: XCTestCase {
    func testCountdownBoundsAndAbsoluteDeadline() throws {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(try AlarmScheduling.countdown(seconds: 30, now: now).timeIntervalSince1970, 1030)
        XCTAssertThrowsError(try AlarmScheduling.countdown(seconds: 0))
        XCTAssertThrowsError(try AlarmScheduling.countdown(seconds: -1))
        XCTAssertThrowsError(try AlarmScheduling.countdown(seconds: AlarmScheduling.maximumDuration + 1))
        XCTAssertNoThrow(try AlarmScheduling.countdown(seconds: AlarmScheduling.maximumDuration))
    }
    func testClockTimeTodayTomorrowAndDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let skipped = try AlarmScheduling.nextTime(hour: 2, minute: 30, now: now, calendar: calendar)
        XCTAssertGreaterThan(skipped, now)
        XCTAssertEqual(calendar.component(.day, from: skipped), 8)
        XCTAssertEqual(calendar.component(.hour, from: skipped), 3)
        let next = try AlarmScheduling.nextTime(hour: 23, minute: 0, now: now, calendar: calendar)
        XCTAssertGreaterThan(next, now) // A matching minute in the past must select tomorrow.
        XCTAssertEqual(calendar.component(.day, from: next), 8)
        XCTAssertThrowsError(try AlarmScheduling.nextTime(hour: 24, minute: 0))
    }
    func testChallengeCannotSkipTypingOrWrongAnswers() {
        var challenge = WakeChallenge(typing: true, mathCount: 3)
        XCTAssertEqual(challenge.code.count, 8)
        XCTAssertFalse(challenge.submit(answer: challenge.left + challenge.right))
        XCTAssertFalse(challenge.submit(code: "wrong"))
        XCTAssertTrue(challenge.submit(code: challenge.code))
        XCTAssertFalse(challenge.submit(answer: -1))
        for remaining in stride(from: 3, through: 1, by: -1) {
            XCTAssertEqual(challenge.remaining, remaining)
            XCTAssertTrue(challenge.submit(answer: challenge.left + challenge.right))
        }
        XCTAssertTrue(challenge.complete)
        XCTAssertFalse(challenge.submit(answer: 0))
    }
    func testPersistenceBackupAndPerAlarmSoundSnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = StateRepository(url: folder.appendingPathComponent("state.json"))
        XCTAssertEqual(try repository.load(), SavedState())
        var first = SavedState()
        first.alarms = [AlarmRecord(target: Date(), isTimer: true, ringtoneID: "custom-a", soundFilename: "a.wav", soundName: "First", typing: true, mathCount: 2)]
        try repository.save(first)
        var second = first
        second.settings.ringtoneID = "custom-b"
        second.importedSounds = [ImportedSound(id: "custom-b", name: "Second", filename: "b.wav")]
        try repository.save(second)
        XCTAssertEqual(try repository.load(), second)
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: repository.backupURL)), first)
        XCTAssertEqual(try repository.load().alarms[0].soundFilename, "a.wav")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(second))
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
    func testUnsafeSoundPathsAndFutureSchemaRejected() throws {
        var state = SavedState()
        state.importedSounds = [ImportedSound(id: "bad", name: "Bad", filename: "../state.json")]
        XCTAssertThrowsError(try state.validated())
        state = SavedState(); state.version = 2
        XCTAssertThrowsError(try state.validated())
    }
    func testSystemReconciliationPreservesActiveAlarmsAndDoesNotResurrectStoppedOnes() {
        let now = Date(timeIntervalSince1970: 1000)
        let active = AlarmRecord(target: now.addingTimeInterval(-1), isTimer: true, ringtoneID: "siren", soundFilename: "siren.wav", soundName: "Siren", typing: false, mathCount: 0)
        var stopped = active; stopped.id = UUID()
        var challenge = active; challenge.id = UUID(); challenge.typing = true
        var lost = active; lost.id = UUID(); lost.target = now.addingTimeInterval(100)
        let result = AlarmReconciliation.reconcile([active, stopped, challenge, lost], systemIDs: [active.id], stoppedIDs: [challenge.id], now: now)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first(where: { $0.id == active.id })?.status, .scheduled)
        XCTAssertNil(result.first(where: { $0.id == stopped.id }))
        XCTAssertEqual(result.first(where: { $0.id == challenge.id })?.status, .needsChallenge)
        XCTAssertEqual(result.first(where: { $0.id == lost.id })?.status, .notScheduled)
    }
    func testMathAutomaticallySubmitsOnlyAtExpectedDigitCount() {
        var challenge = WakeChallenge(typing: false, mathCount: 3)
        for remaining in stride(from: 3, through: 1, by: -1) {
            let correct = String(challenge.left + challenge.right)
            XCTAssertEqual(challenge.answerDigitCount, correct.count)
            XCTAssertEqual(challenge.submit(digits: String(correct.dropLast())), .incomplete)
            XCTAssertEqual(challenge.remaining, remaining)
            XCTAssertEqual(challenge.submit(digits: correct.count == 1 ? "0" : "99"), .incorrect)
            XCTAssertEqual(challenge.remaining, remaining)
            XCTAssertEqual(challenge.submit(digits: correct), .correct)
        }
        XCTAssertTrue(challenge.complete)
        var typing = WakeChallenge(typing: true, mathCount: 1)
        XCTAssertEqual(typing.submit(digits: String(typing.left + typing.right)), .incomplete)
    }
    func testSoundPreferencesRemainCompatibleWithEarlierSavedSettings() throws {
        let old = try JSONDecoder().decode(AlarmSettings.self, from: JSONEncoder().encode(AlarmSettings()))
        XCTAssertNil(old.soundLevel)
        XCTAssertNil(old.soundCheckCompleted)
        var state = SavedState(); state.settings.soundLevel = 0.5; state.settings.soundCheckCompleted = true
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)).validated(), state)
        state.settings.soundLevel = 0
        XCTAssertThrowsError(try state.validated())
    }
}
