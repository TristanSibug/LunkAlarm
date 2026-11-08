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
        XCTAssertEqual(hour.value as? String, "7")
        period.adjust(toPickerWheelValue: "AM")
        hour.adjust(toPickerWheelValue: "11")
        hour.adjust(toPickerWheelValue: "12")
        XCTAssertEqual(period.value as? String, "PM")
        period.adjust(toPickerWheelValue: "PM")
        hour.adjust(toPickerWheelValue: "11")
        hour.adjust(toPickerWheelValue: "12")
        XCTAssertEqual(period.value as? String, "AM")
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
        capture(app, name: "ios-problem-wheel")
    }
    @MainActor func testMathEntryAdvancesWithoutOKAndClearsWrongAnswer() {
        let app = launch(mathAlarm: true)
        let problem = app.staticTexts["mathProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["OK"].exists)
        XCTAssertEqual(app.switches["challengeSoundToggle"].value as? String, "0")
        let numbers = problem.label.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(numbers.count, 2)
        let answer = String(numbers.reduce(0, +))
        for character in answer.count == 1 ? "0" : "99" { app.buttons[String(character)].tap() }
        XCTAssertEqual(app.staticTexts["mathAnswer"].label, "Your answer")
        for remaining in stride(from: 3, through: 1, by: -1) {
            XCTAssertTrue(app.staticTexts["mathProgress"].label.hasPrefix("\(3 - remaining) /"))
            let values = problem.label.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            for digit in String(values.reduce(0, +)) { app.buttons[String(digit)].tap() }
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
        app.switches["challengeSoundToggle"].tap()
        XCTAssertEqual(app.switches["challengeSoundToggle"].value as? String, "0")
        capture(app, name: "ios-timed-math")
    }
}
