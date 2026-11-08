import XCTest

final class AlarmInteractionTests: XCTestCase {
    @MainActor
    private func launch(mathAlarm: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (mathAlarm ? ["--ui-math-alarm"] : [])
        app.launch()
        return app
    }
    @MainActor private func openEditor(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 10))
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.staticTexts["New alarm"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testSwipeNavigationAndNativeTimeWheel() {
        let app = launch()
        XCTAssertFalse(app.buttons["alarmPickerToggle"].exists)
        openEditor(app)
        let picker = app.datePickers["alarmTimePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.pickerWheels.count, 3)
        let hour = picker.pickerWheels.element(boundBy: 0)
        let period = picker.pickerWheels.element(boundBy: 2)
        XCTAssertEqual((hour.value as? String)?.filter(\.isNumber), "7")
        period.adjust(toPickerWheelValue: "AM")
        hour.adjust(toPickerWheelValue: "11")
        hour.adjust(toPickerWheelValue: "12")
        let noon = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'PM'"), object: period)
        wait(for: [noon], timeout: 5)
        hour.adjust(toPickerWheelValue: "11")
        period.adjust(toPickerWheelValue: "PM")
        hour.adjust(toPickerWheelValue: "12")
        let midnight = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'AM'"), object: period)
        wait(for: [midnight], timeout: 5)
        capture(app, name: "ios-alarm-time")
        // A fast downward adjustment of the picker must not close the page.
        picker.swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["New alarm"].exists)
        let hint = app.descendants(matching: .any)["alarmSwipeHint"]
        let start = hint.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 160))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["New alarm"])
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].exists)
    }
    @MainActor func testLoopingProblemCountAndFourPresets() {
        let app = launch()
        openEditor(app)
        app.buttons["In how long"].tap()
        XCTAssertFalse(app.buttons["8 hours"].exists)
        let math = app.switches["mathTestToggle"]
        for _ in 0..<4 where !math.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(math.isHittable)
        math.tap()
        let picker = app.pickers["mathProblemPicker"]
        for _ in 0..<3 where !picker.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let wheel = picker.pickerWheels.firstMatch
        wheel.adjust(toPickerWheelValue: "8")
        XCTAssertEqual(wheel.value as? String, "8")
        wheel.swipeUp(velocity: .slow)
        XCTAssertNotEqual(wheel.value as? String, "8")
        XCTAssertNotNil(Int(wheel.value as? String ?? ""))
        wheel.adjust(toPickerWheelValue: "1")
        wheel.swipeDown(velocity: .slow)
        XCTAssertNotEqual(wheel.value as? String, "1")
        let timer = app.pickers["mathTimerPicker"]
        XCTAssertTrue(timer.exists)
        XCTAssertEqual(picker.frame.midY, timer.frame.midY, accuracy: 2)
        timer.pickerWheels.firstMatch.adjust(toPickerWheelValue: "5")
        XCTAssertEqual(timer.pickerWheels.firstMatch.value as? String, "5")
        timer.pickerWheels.firstMatch.adjust(toPickerWheelValue: "12")
        XCTAssertEqual(timer.pickerWheels.firstMatch.value as? String, "12")
        capture(app, name: "ios-problem-wheel")
    }
    @MainActor func testMathEntryAdvancesWithoutOKAndClearsWrongAnswer() {
        let app = launch(mathAlarm: true)
        let problem = app.staticTexts["mathProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["OK"].exists)
        XCTAssertEqual(app.switches["challengeSoundToggle"].value as? String, "0")
        for remaining in stride(from: 3, through: 1, by: -1) {
            XCTAssertTrue(app.staticTexts["mathProgress"].label.hasPrefix("\(3 - remaining) /"))
            let values = problem.label.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            XCTAssertEqual(values.count, 2)
            let answer = String(values.reduce(0, +))
            if remaining == 2 {
                for digit in answer.count == 1 ? "0" : "99" { app.buttons[String(digit)].tap() }
                XCTAssertEqual(app.staticTexts["mathAnswer"].label, "Your answer")
            }
            for digit in answer { app.buttons[String(digit)].tap() }
        }
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alarm dismissed. Have a good day."].exists)
    }
    @MainActor func testMathTimeoutResetsProgressAndEnablesSound() {
        let app = launch(mathAlarm: true)
        let problem = app.staticTexts["mathProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        let values = problem.label.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        for digit in String(values.reduce(0, +)) { app.buttons[String(digit)].tap() }
        XCTAssertTrue(app.staticTexts["mathProgress"].label.hasPrefix("1 /"))
        let progressReset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH '0 /'"), object: app.staticTexts["mathProgress"])
        wait(for: [progressReset], timeout: 14)
        XCTAssertEqual(app.switches["challengeSoundToggle"].value as? String, "1")
        let sound = app.switches["challengeSoundToggle"]
        sound.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let muted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: sound)
        wait(for: [muted], timeout: 3)
        capture(app, name: "ios-timed-math")
    }
    @MainActor func testTypingWheelsCollapseAndCompactSoundCheck() {
        let app = launch()
        openEditor(app)
        let typing = app.switches["typingTestToggle"]
        for _ in 0..<5 where !typing.isHittable { app.swipeUp(velocity: .slow) }
        typing.tap()
        let length = app.pickers["typingLengthPicker"]
        for _ in 0..<4 where !length.isHittable { app.swipeUp(velocity: .slow) }
        let timer = app.pickers["typingTimerPicker"]
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertTrue(timer.exists)
        XCTAssertEqual(length.frame.midY, timer.frame.midY, accuracy: 2)
        length.pickerWheels.firstMatch.adjust(toPickerWheelValue: "10")
        XCTAssertEqual(length.pickerWheels.firstMatch.value as? String, "10")
        length.pickerWheels.firstMatch.adjust(toPickerWheelValue: "4")
        timer.pickerWheels.firstMatch.adjust(toPickerWheelValue: "15")
        XCTAssertEqual(timer.pickerWheels.firstMatch.value as? String, "15")
        timer.pickerWheels.firstMatch.adjust(toPickerWheelValue: "30")
        capture(app, name: "ios-typing-wheels")
        let disclosure = app.buttons["wakeTestsDisclosure"]
        for _ in 0..<4 where !disclosure.isHittable { app.swipeDown(velocity: .slow) }
        disclosure.tap()
        XCTAssertFalse(app.pickers["typingLengthPicker"].exists)
        XCTAssertFalse(app.switches["typingTestToggle"].exists)
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertTrue(app.buttons["scheduleAlarm"].exists)
        let check = app.buttons["Check alarm sound"]
        for _ in 0..<4 where !check.isHittable { app.swipeDown(velocity: .slow) }
        check.tap()
        let preview = app.buttons["previewAlarmSound"]
        let test = app.buttons["testAlarmSound"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(test.exists)
        XCTAssertEqual(preview.frame.midY, test.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(test.frame.minX, preview.frame.maxX)
        XCTAssertFalse(app.buttons["Use this level and add alarm"].exists)
        capture(app, name: "ios-sound-check")
    }
    @MainActor func testRingtoneActionsLiveInsideChooserAndOpenOnlineSheet() {
        let app = launch()
        openEditor(app)
        XCTAssertFalse(app.buttons["Use my own file"].exists)
        let tone = app.buttons.containing(.staticText, identifier: "Classic Beep").firstMatch
        for _ in 0..<4 where !tone.isHittable { app.swipeUp(velocity: .slow) }
        tone.tap()
        XCTAssertTrue(app.buttons["Use my own file"].waitForExistence(timeout: 5))
        app.buttons["Find more ringtones online"].tap()
        XCTAssertTrue(app.navigationBars["Find more ringtones"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ringtoneProviderMixkit"].exists)
    }

}
