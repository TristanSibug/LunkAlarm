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
    func testTimedTypingThenMathAndTimeoutResetsEntireSequence() {
        let start = Date(timeIntervalSince1970: 1000)
        var test = TimedWakeChallenge(typing: true, mathCount: 3, now: start)
        XCTAssertEqual(test.secondsRemaining(now: start), 30)
        XCTAssertTrue(test.submit(code: test.code, now: start.addingTimeInterval(29)))
        XCTAssertEqual(test.deadline, start.addingTimeInterval(39))
        XCTAssertEqual(test.submit(digits: String(test.left + test.right), now: start.addingTimeInterval(32)), .correct)
        XCTAssertEqual(test.answered, 1)
        XCTAssertEqual(test.deadline, start.addingTimeInterval(42))
        XCTAssertFalse(test.expireIfNeeded(now: start.addingTimeInterval(41.9)))
        XCTAssertTrue(test.expireIfNeeded(now: start.addingTimeInterval(42)))
        XCTAssertTrue(test.typingPending)
        XCTAssertEqual(test.answered, 0)
        XCTAssertEqual(test.remaining, 3)
        XCTAssertEqual(test.resetCount, 1)
        XCTAssertEqual(test.deadline, start.addingTimeInterval(72))
    }
    func testLateMathAnswerCannotPassAndWrongAnswersDoNotExtendDeadline() {
        let start = Date(timeIntervalSince1970: 1000)
        var test = TimedWakeChallenge(typing: false, mathCount: 2, now: start)
        XCTAssertEqual(test.deadline, start.addingTimeInterval(10))
        XCTAssertEqual(test.submit(digits: "99", now: start.addingTimeInterval(9)), .incorrect)
        XCTAssertEqual(test.deadline, start.addingTimeInterval(10))
        XCTAssertEqual(test.submit(digits: String(test.left + test.right), now: start.addingTimeInterval(10)), .timedOut)
        XCTAssertEqual(test.answered, 0)
        XCTAssertEqual(test.resetCount, 1)
        XCTAssertEqual(test.deadline, start.addingTimeInterval(20))
        XCTAssertEqual(test.submit(digits: String(test.left + test.right), now: start.addingTimeInterval(11)), .correct)
        XCTAssertEqual(test.submit(digits: String(test.left + test.right), now: start.addingTimeInterval(12)), .correct)
        XCTAssertTrue(test.complete)
        XCTAssertNil(test.deadline)
        XCTAssertFalse(test.expireIfNeeded(now: start.addingTimeInterval(100)))
    }
    func testGradualVolumeStartsAtZeroAndNeverExceedsSelectedLevel() {
        XCTAssertEqual(AlarmSoundLevel.gain(level: 0.6, elapsed: 0, gradual: true), 0)
        XCTAssertEqual(AlarmSoundLevel.gain(level: 0.6, elapsed: 5, gradual: true), 0.3, accuracy: 0.0001)
        XCTAssertEqual(AlarmSoundLevel.gain(level: 0.6, elapsed: 10, gradual: true), 0.6)
        XCTAssertEqual(AlarmSoundLevel.gain(level: 0.6, elapsed: 100, gradual: true), 0.6)
        XCTAssertEqual(AlarmSoundLevel.gain(level: 0.6, elapsed: 0, gradual: false), 0.6)
    }
    func testTimeoutAlarmIDsAndSoundSnapshotSurvivePersistence() throws {
        var state = SavedState()
        var alarm = AlarmRecord(target: Date(), isTimer: true, ringtoneID: "classic-beep", soundFilename: "fade10-60-classic-beep.wav", soundName: "Classic Beep", typing: true, mathCount: 3, status: .needsChallenge)
        let nativeTimeout = UUID()
        alarm.challengeAlarmIDs = [nativeTimeout]
        alarm.playbackSoundFilename = "classic-beep.wav"; alarm.soundLevel = 0.6; alarm.gradualVolume = true
        state.alarms = [alarm]
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)).validated()
        XCTAssertEqual(restored.alarms[0], alarm)
        XCTAssertTrue(restored.alarms[0].nativeAlarmIDs.contains(nativeTimeout))
        state.alarms[0].challengeAlarmIDs = [alarm.id]
        XCTAssertThrowsError(try state.validated())
    }
    func testTimeWheelCrossesNoonMidnightAndSupportsManualPeriodChanges() {
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 11, selected: 0, use24Hour: false), 12)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 23, selected: 12, use24Hour: false), 0)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 12, selected: 23, use24Hour: false), 11)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 0, selected: 11, use24Hour: false), 23)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 7, selected: 19, use24Hour: false), 19)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 12, selected: 0, use24Hour: false), 0)
        XCTAssertEqual(AlarmTimeWheel.resolvedHour(previous: 23, selected: 12, use24Hour: true), 12)
    }
    func testSelectedCodeLengthsAndTimersSurviveEveryReset() {
        let start = Date(timeIntervalSince1970: 1000)
        for length in WakeTestOptions.codeLengths {
            for typingTime in [15, 30] {
                for mathTime in [5, 12] {
                    var test = TimedWakeChallenge(typing: true, mathCount: 2, codeLength: length,
                        typingTimeLimit: typingTime, mathTimeLimit: mathTime, now: start)
                    XCTAssertEqual(test.code.count, length)
                    XCTAssertEqual(test.deadline, start.addingTimeInterval(Double(typingTime)))
                    XCTAssertTrue(test.submit(code: test.code, now: start.addingTimeInterval(1)))
                    let firstDeadline = start.addingTimeInterval(Double(1 + mathTime))
                    XCTAssertEqual(test.deadline, firstDeadline)
                    XCTAssertEqual(test.submit(digits: String(test.left + test.right), now: start.addingTimeInterval(2)), .correct)
                    XCTAssertEqual(test.answered, 1)
                    let expiry = start.addingTimeInterval(Double(2 + mathTime))
                    XCTAssertTrue(test.expireIfNeeded(now: expiry))
                    XCTAssertEqual(test.code.count, length)
                    XCTAssertTrue(test.typingPending)
                    XCTAssertEqual(test.answered, 0)
                    XCTAssertEqual(test.deadline, expiry.addingTimeInterval(Double(typingTime)))
                }
            }
        }
    }
    func testWakeTestSettingsAreOptionalValidatedAndSnapshottedPerAlarm() throws {
        var state = SavedState()
        var alarm = AlarmRecord(target: Date(), isTimer: true, ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: true, mathCount: 3)
        alarm.typingCodeLength = 10; alarm.typingTimeLimit = 15; alarm.mathTimeLimit = 5
        state.alarms = [alarm]
        state.settings.typingCodeLength = 4; state.settings.typingTimeLimit = 30; state.settings.mathTimeLimit = 12
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)).validated()
        XCTAssertEqual(restored.alarms[0].typingCodeLength, 10)
        XCTAssertEqual(restored.alarms[0].typingTimeLimit, 15)
        XCTAssertEqual(restored.alarms[0].mathTimeLimit, 5)
        XCTAssertEqual(restored.settings.typingCodeLength, 4)
        // An older installation has no new keys; defaults remain 8 / 30 / 10.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        for key in ["typingCodeLength", "typingTimeLimit", "mathTimeLimit"] { settings.removeValue(forKey: key) }
        object["settings"] = settings
        let old = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.settings.typingCodeLength)
        XCTAssertNil(old.settings.typingTimeLimit)
        XCTAssertNil(old.settings.mathTimeLimit)
        state.settings.typingCodeLength = 3; XCTAssertThrowsError(try state.validated())
        state.settings.typingCodeLength = 11; XCTAssertThrowsError(try state.validated())
        state.settings.typingCodeLength = 4
        state.settings.typingTimeLimit = 14; XCTAssertThrowsError(try state.validated())
        state.settings.typingTimeLimit = 31; XCTAssertThrowsError(try state.validated())
        state.settings.typingTimeLimit = 15
        state.alarms[0].mathTimeLimit = 4; XCTAssertThrowsError(try state.validated())
        state.alarms[0].mathTimeLimit = 13; XCTAssertThrowsError(try state.validated())
    }
    func testFailedUnlockPreservesChallengeEvenWhileRecoveryIsScheduled() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var alarm = AlarmRecord(target: start, isTimer: true, ringtoneID: "classic-beep", soundFilename: "classic-beep.wav", soundName: "Classic Beep", typing: false, mathCount: 3)
        let recovery = UUID()
        alarm.challengeAlarmIDs = [recovery]
        let result = AlarmReconciliation.reconcile([alarm], systemIDs: [recovery], stoppedIDs: [], now: start.addingTimeInterval(1))
        XCTAssertEqual(result.first?.status, .needsChallenge)
        XCTAssertEqual(result.first?.nativeAlarmIDs, [alarm.id, recovery])
        let dates = AlarmRecovery.dates(after: start)
        XCTAssertEqual(dates.map { $0.timeIntervalSince(start) }, [20, 40, 60])
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertTrue(dates.allSatisfy { $0 > start })
    }

}
