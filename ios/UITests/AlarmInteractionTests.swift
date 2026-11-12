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
        XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].waitForExistence(timeout: 5))
        app.buttons["newAlarmButton"].tap()
        app.buttons["Alarm"].tap()
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
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.segmentedControls["playbackEngine"].exists)
        XCTAssertFalse(app.buttons["Continuous audio"].exists)
        XCTAssertTrue(app.buttons["scheduleAlarm"].isHittable)
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
        app.buttons["closeAlarmEditor"].tap()
        XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].waitForExistence(timeout: 5))
        app.buttons["Clock"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 5))
    }
    // Scroll in the editor gutter, away from the native wheels and sliders.
    @MainActor private func scrollEditor(_ app: XCUIApplication, up: Bool = true) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.76 : 0.28))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.28 : 0.76))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    @MainActor private func openTest(_ app: XCUIApplication, _ kind: String) {
        let tile = app.buttons["test-tile-" + kind]
        let save = app.buttons["scheduleAlarm"]
        for _ in 0..<8 where !tile.isHittable || tile.frame.maxY > save.frame.minY - 10 { scrollEditor(app) }
        XCTAssertTrue(tile.isHittable)
        tile.tap()
        XCTAssertTrue(app.buttons["try-" + kind].waitForExistence(timeout: 5))
    }
    @MainActor func testBoundedProblemButtonsAndFourPresets() {
        let app = launch(); openEditor(app)
        XCTAssertFalse(app.buttons["In how long"].exists)
        XCTAssertFalse(app.buttons["8 hours"].exists)
        openTest(app, "math")
        XCTAssertFalse(app.pickers["mathProblemPicker"].exists)
        for _ in 0..<5 { app.buttons["math-count-plus"].tap() }
        XCTAssertEqual(app.staticTexts["math-count-value"].label, "8")
        XCTAssertFalse(app.buttons["math-count-plus"].isEnabled)
        for _ in 0..<7 { app.buttons["math-count-minus"].tap() }
        XCTAssertEqual(app.staticTexts["math-count-value"].label, "1")
        XCTAssertFalse(app.buttons["math-count-minus"].isEnabled)
        app.buttons["math-timer-15"].tap()
        XCTAssertTrue(app.buttons["math-timer-15"].isSelected)
        XCTAssertGreaterThanOrEqual(app.buttons["try-math"].frame.width, 88)
        capture(app, name: "ios-math-buttons")
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
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit Timer"].exists)
        XCTAssertTrue(app.staticTexts["No alarms or timers yet. Tap + to add one."].exists)
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
    @MainActor func testTypingButtonsCollapseAndCompactSoundCheck() {
        let app = launch(); openEditor(app); openTest(app, "typing")
        for _ in 0..<2 { app.buttons["typing-length-plus"].tap() }
        XCTAssertEqual(app.staticTexts["typing-length-value"].label, "10")
        XCTAssertFalse(app.buttons["typing-length-plus"].isEnabled)
        app.buttons["typing-timer-15"].tap(); XCTAssertTrue(app.buttons["typing-timer-15"].isSelected)
        XCTAssertGreaterThanOrEqual(app.buttons["try-typing"].frame.width, 88)
        capture(app, name: "ios-typing-buttons")
        app.buttons["testSettingsDone"].tap()
        XCTAssertFalse(app.buttons["wakeTestsDisclosure"].exists)
        XCTAssertTrue(app.buttons["test-tile-typing"].isSelected)
        XCTAssertTrue(app.buttons["scheduleAlarm"].exists)
        let vibration = app.buttons["inAppVibration"]
        for _ in 0..<5 where !vibration.isHittable { scrollEditor(app, up: false) }
        vibration.tap(); XCTAssertEqual(vibration.value as? String, "On")
        app.buttons["Check alarm sound"].tap()
        let preview = app.buttons["previewAlarmSound"], test = app.buttons["testAlarmSound"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertTrue(test.exists)
        XCTAssertEqual(preview.frame.midY, test.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(test.frame.minX, preview.frame.maxX)
        XCTAssertFalse(app.buttons["Use this level and add alarm"].exists)
        capture(app, name: "ios-sound-check-vibration")
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

    @MainActor func testSavedAlarmNameDaysAndDisablePersistInList() {
        let app = launch()
        openEditor(app)
        let name = app.textFields["alarmNameField"]
        name.tap(); name.typeText("Morning routine")
        app.swipeUp(velocity: .slow)
        let add = app.buttons["scheduleAlarm"]
        for _ in 0..<8 where !add.isHittable { app.swipeUp(velocity: .slow) }
        add.tap()
        XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Morning routine")).firstMatch.exists)
        let toggle = app.switches["Enable Morning routine"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Morning routine")).firstMatch.exists)
        capture(app, name: "ios-saved-alarms")
    }

    @MainActor private func saveEditor(_ app: XCUIApplication) {
        let save = app.buttons["scheduleAlarm"]
        for _ in 0..<9 where !save.isHittable { app.swipeUp(velocity: .slow) }
        save.tap()
        // The list already exists behind the editor. Wait for modal dismissal,
        // otherwise the next tap can land on the outgoing editor's backdrop.
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["closeAlarmEditor"])
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].exists || app.staticTexts["timersTitle"].exists)
    }
    @MainActor private func returnToClock(_ app: XCUIApplication) {
        app.buttons["Clock"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["savedAlarmsTitle"])
        wait(for: [finished], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 5))
    }
    @MainActor func testBlankNameEditInPlaceAndExactDuplicate() {
        let app = launch()
        openEditor(app)
        saveEditor(app)
        let blankCards = app.buttons.matching(NSPredicate(format: "label == %@", "Edit Alarm"))
        XCTAssertEqual(blankCards.count, 1)
        blankCards.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit alarm"].waitForExistence(timeout: 5))
        let name = app.textFields["alarmNameField"]
        name.tap(); name.typeText("Same alarm")
        saveEditor(app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Same alarm")).count, 1)
        app.buttons["Options for Same alarm"].tap()
        app.buttons["Duplicate"].tap()
        let duplicated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.buttons.matching(NSPredicate(format: "label == %@", "Edit Same alarm")))
        wait(for: [duplicated], timeout: 5)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Same alarm")).count, 2)
        capture(app, name: "ios-compact-duplicates")
    }

    @MainActor func testCountdownIsInYourAlarmsAndCanBeEdited() {
        let app = launch()
        openEditor(app)
        app.buttons["closeAlarmEditor"].tap()
        app.buttons["newAlarmButton"].tap(); app.buttons["Timer"].tap()
        XCTAssertTrue(app.navigationBars["New timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["alarmNameField"].exists)
        XCTAssertEqual(app.buttons["scheduleAlarm"].label, "Add timer")
        saveEditor(app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Timer")).count, 1)
        let card = app.buttons["Edit Timer"]
        card.tap()
        XCTAssertTrue(app.navigationBars["Edit timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["alarmNameField"].exists)
        XCTAssertFalse(app.buttons["At a time"].exists)
        XCTAssertFalse(app.buttons["In how long"].exists)
        XCTAssertEqual(app.buttons["scheduleAlarm"].label, "Save changes")
        XCTAssertTrue(app.buttons["scheduleAlarm"].isHittable)
        capture(app, name: "ios-floating-save-timer")
        saveEditor(app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Edit Timer")).count, 1)
        capture(app, name: "ios-countdown-in-list")
    }
    @MainActor func testEmptyAndPopulatedHeaderAlignmentAndFloatingEditorButton() {
        let app = launch()
        app.swipeUp(velocity: .fast)
        let title = app.staticTexts["savedAlarmsTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let emptyX = title.frame.minX
        let emptyClockX = app.buttons["Clock"].frame.minX
        capture(app, name: "ios-aligned-empty-list")
        app.buttons["newAlarmButton"].tap()
        app.buttons["Alarm"].tap()
        let save = app.buttons["scheduleAlarm"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable)
        let initialY = save.frame.midY
        app.swipeUp(velocity: .slow)
        XCTAssertEqual(save.frame.midY, initialY, accuracy: 2)
        capture(app, name: "ios-floating-add-button")
        saveEditor(app)
        XCTAssertEqual(title.frame.minX, emptyX, accuracy: 1)
        XCTAssertEqual(app.buttons["Clock"].frame.minX, emptyClockX, accuracy: 1)
        XCTAssertEqual(emptyX, 20, accuracy: 2)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 5))
    }
    @MainActor func testPartialSwipeRevealsDeleteAndFullSwipeDeletesWithoutOpeningEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-mixed-alarms"]
        app.launch()
        app.swipeUp(velocity: .fast)
        let timer = app.buttons["Edit Timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.staticTexts["timersTitle"].frame.minY, app.staticTexts["savedAlarmsTitle"].frame.minY)
        let start = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let partial = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: partial)
        let delete = app.buttons["swipeDeleteAlarm"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Edit alarm"].exists)
        capture(app, name: "ios-swipe-reveal-delete")
        delete.tap()
        let timerGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: timer)
        wait(for: [timerGone], timeout: 5)
        let routine = app.buttons["Edit Morning"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: routine)
        wait(for: [ready], timeout: 5)
        // The edit button excludes the toggle and card padding. A full card
        // swipe must cross the row's threshold, rather than that shorter label.
        let swipeY = routine.frame.midY / app.frame.height
        let fullStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: swipeY))
        let fullEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: swipeY))
        fullStart.press(forDuration: 0.1, thenDragTo: fullEnd)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: routine)
        wait(for: [gone], timeout: 5)
        capture(app, name: "ios-full-swipe-delete")
        XCTAssertTrue(app.staticTexts["No alarms or timers yet. Tap + to add one."].exists)
        XCTAssertFalse(app.navigationBars["Edit alarm"].exists)
    }
    @MainActor func testTypingKeyboardAcceptsOneCharacterAndBackspace() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-typing-alarm"]
        app.launch()
        let field = app.textFields["wakeCodeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("aB3")
        XCTAssertEqual(field.value as? String, "aB3")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "aB")
        capture(app, name: "ios-typing-keyboard")
    }
    @MainActor private func chooseCustomRepeatDays(_ app: XCUIApplication) {
        let daily = app.buttons["dailyRepeat"]
        let save = app.buttons["scheduleAlarm"]
        for _ in 0..<5 where !daily.isHittable || daily.frame.maxY > save.frame.minY - 12 { app.swipeUp(velocity: .slow) }
        daily.tap() // New alarms default to all seven days; clear them first.
        app.buttons["Tuesday"].tap()
        app.buttons["Friday"].tap()
    }
    @MainActor func testRepeatDaysUseSelectedCirclesAndAllDaysUseDaily() {
        let app = launch()
        openEditor(app)
        saveEditor(app)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editAlarm-' ")).firstMatch
        let id = String(edit.identifier.dropFirst("editAlarm-".count))
        XCTAssertTrue(app.staticTexts["alarmDaily-\(id)"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["alarmWeekdays-\(id)"].exists)
        capture(app, name: "ios-repeat-daily")
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit alarm"].waitForExistence(timeout: 5))
        chooseCustomRepeatDays(app)
        saveEditor(app)
        XCTAssertFalse(app.staticTexts["alarmDaily-\(id)"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["alarmWeekdays-\(id)"].exists)
        for day in 1...7 {
            let badge = app.descendants(matching: .any)["alarmDay-\(id)-\(day)"]
            XCTAssertTrue(badge.exists)
            XCTAssertEqual(badge.value as? String, [3, 6].contains(day) ? "Selected" : "Not selected")
        }
        XCTAssertFalse(app.staticTexts["Tue"].exists)
        XCTAssertFalse(app.staticTexts["Tue · Fri"].exists)
        capture(app, name: "ios-repeat-selected-circles")
        edit.tap()
        let daily = app.buttons["dailyRepeat"]
        for _ in 0..<5 where !daily.isHittable { app.swipeUp(velocity: .slow) }
        daily.tap()
        saveEditor(app)
        XCTAssertTrue(app.staticTexts["alarmDaily-\(id)"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["alarmWeekdays-\(id)"].exists)
    }
    @MainActor func testFiveNewThemesRenderClockAndRepeatCards() {
        let app = launch()
        openEditor(app)
        chooseCustomRepeatDays(app)
        saveEditor(app)
        app.buttons["newAlarmButton"].tap()
        app.buttons["Alarm"].tap()
        let daily = app.buttons["dailyRepeat"]
        for _ in 0..<5 where !daily.isHittable { app.swipeUp(velocity: .slow) }
        daily.tap() // The previous custom days are remembered; select all for this alarm.
        saveEditor(app)
        returnToClock(app)
        for name in ["Eggshell White", "Heritage", "Midnight Cherry", "Cobalt & Coral", "Signal Blue"] {
            app.buttons["Theme"].tap()
            XCTAssertTrue(app.navigationBars["Theme"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))
            let choice = app.buttons[name]
            for _ in 0..<12 where !choice.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
            XCTAssertTrue(choice.isHittable, "Theme must be reachable: \(name)")
            choice.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Theme"])
            wait(for: [dismissed], timeout: 5)
            XCTAssertTrue(app.descendants(matching: .any)["alarmSwipeHint"].waitForExistence(timeout: 5))
            capture(app, name: "ios-theme-\(name)-clock")
            app.swipeUp(velocity: .fast)
            XCTAssertTrue(app.staticTexts["savedAlarmsTitle"].waitForExistence(timeout: 5))
            capture(app, name: "ios-theme-\(name)-alarms")
            returnToClock(app)
        }
    }

    @MainActor func testTypingPracticeStaysOpenWhenKeyboardAppears() {
        let app = launch(); openEditor(app); openTest(app, "typing")
        app.buttons["try-typing"].tap()
        let field = app.textFields["wakeCodeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("aB3")
        XCTAssertEqual(field.value as? String, "aB3")
        XCTAssertTrue(app.buttons["exitPractice"].isHittable)
        XCTAssertTrue(app.staticTexts["challengeCode"].exists)
        capture(app, name: "ios-practice-typing-keyboard")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "aB")
        app.buttons["exitPractice"].tap()
        XCTAssertTrue(app.buttons["try-typing"].waitForExistence(timeout: 5))
    }
    @MainActor func testPracticeCompletionHasRetryAndCloseWithoutBackToSettings() {
        let app = launch(); openEditor(app); openTest(app, "math")
        app.buttons["math-count-minus"].tap(); app.buttons["math-count-minus"].tap()
        app.buttons["math-timer-15"].tap(); app.buttons["try-math"].tap()
        let problem = app.staticTexts["mathProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        let sum = problem.label.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
        for digit in String(sum) { app.buttons[String(digit)].tap() }
        XCTAssertTrue(app.buttons["retryPractice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back to settings"].exists)
        capture(app, name: "ios-practice-complete")
        app.buttons["retryPractice"].tap()
        XCTAssertTrue(app.staticTexts["mathProblem"].exists)
        app.buttons["exitPractice"].tap(); app.buttons["testSettingsDone"].tap()
        app.buttons["closeAlarmEditor"].tap()
        XCTAssertTrue(app.staticTexts["No alarms or timers yet. Tap + to add one."].exists)
    }
    @MainActor private func assertSquareBoard(_ app: XCUIApplication, prefix: String, size: Int) {
        let first = app.descendants(matching: .any)[prefix + "0"].frame
        let last = app.descendants(matching: .any)[prefix + "\(size - 1)"].frame
        XCTAssertEqual(first.width, first.height, accuracy: 1, "Empty and numbered cells must be square")
        XCTAssertGreaterThan(last.maxX - first.minX, app.frame.width * 0.75, "The board should fill the available width")
        for row in 1..<size {
            let left = app.descendants(matching: .any)[prefix + "\(row * size)"].frame
            let right = app.descendants(matching: .any)[prefix + "\(row * size + size - 1)"].frame
            XCTAssertEqual(left.minX, first.minX, accuracy: 1)
            XCTAssertEqual(right.maxX, last.maxX, accuracy: 1)
            XCTAssertEqual(left.width, first.width, accuracy: 1)
            XCTAssertEqual(left.height, first.height, accuracy: 1)
            XCTAssertEqual(right.minY, left.minY, accuracy: 1)
        }
    }
    @MainActor func testMinesweeperSizesAndHoldNumberKeepPracticeOpen() {
        let app = launch(); openEditor(app); openTest(app, "mines")
        for level in 0..<3 {
            app.buttons["mine-difficulty-\(level)"].tap()
            XCTAssertTrue(app.buttons["mine-difficulty-\(level)"].isSelected)
            app.buttons["mine-timer-40"].tap(); app.buttons["try-mines"].tap()
            XCTAssertTrue(app.buttons["exitPractice"].waitForExistence(timeout: 5))
            let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'mine-cell-'"))
            XCTAssertEqual(cells.count, [25, 49, 81][level])
            assertSquareBoard(app, prefix: "mine-cell-", size: [5, 7, 9][level])
            let number = cells.matching(NSPredicate(format: "value CONTAINS 'adjacent mines' AND NOT value BEGINSWITH '0 '")).firstMatch
            XCTAssertTrue(number.exists)
            number.press(forDuration: 0.6)
            XCTAssertTrue(app.buttons["exitPractice"].exists)
            capture(app, name: "ios-mine-\(level)-practice")
            app.buttons["exitPractice"].tap()
            XCTAssertTrue(app.buttons["try-mines"].waitForExistence(timeout: 5))
        }
    }
    @MainActor func testGameSettingsTilesAndSudokuTimersPersistOnSameAlarm() {
        let app = launch(); openEditor(app)
        for kind in ["typing", "math", "puzzle", "mines", "sudoku"] {
            openTest(app, kind)
            if kind == "puzzle" {
                app.buttons["puzzle-pieces-10"].tap(); capture(app, name: "ios-puzzle-settings")
                app.buttons["puzzle-timer-40"].tap(); app.buttons["try-puzzle"].tap()
                let piece = app.descendants(matching: .any)["puzzle-piece-0"]
                XCTAssertTrue(piece.waitForExistence(timeout: 5)); piece.tap()
                app.buttons["puzzle-slot-1"].tap()
                XCTAssertEqual(app.staticTexts["puzzleProgress"].label, "0/10 placed")
                app.buttons["puzzle-slot-0"].tap()
                XCTAssertEqual(app.staticTexts["puzzleProgress"].label, "1/10 placed")
                capture(app, name: "ios-puzzle-practice")
                app.buttons["exitPractice"].tap()
            }
            if kind == "mines" { app.buttons["mine-difficulty-2"].tap(); capture(app, name: "ios-mines-settings") }
            if kind == "sudoku" {
                app.buttons["sudoku-difficulty-3"].tap(); app.buttons["sudoku-timer-240"].tap()
                let tops = [60, 120, 180, 240].map { app.buttons["sudoku-timer-\($0)"].frame.minY }
                XCTAssertTrue(tops.allSatisfy { abs($0 - tops[0]) < 1 })
                XCTAssertFalse(app.buttons["sudoku-timer-30"].exists)
                capture(app, name: "ios-sudoku-settings")
            }
            app.buttons["testSettingsDone"].tap()
        }
        for kind in ["typing", "math", "puzzle", "mines", "sudoku"] { XCTAssertTrue(app.buttons["test-tile-" + kind].isSelected) }
        capture(app, name: "ios-wake-test-tiles")
        saveEditor(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editAlarm-' ")).firstMatch.tap()
        let tile = app.buttons["test-tile-sudoku"]
        let save = app.buttons["scheduleAlarm"]
        for _ in 0..<8 where !tile.isHittable || tile.frame.maxY > save.frame.minY - 10 { scrollEditor(app) }
        tile.tap(); XCTAssertTrue(app.buttons["try-sudoku"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["testSettingsDone"].label, "Unset")
        app.buttons["closeTestSettings"].tap()
        XCTAssertTrue(tile.isSelected)
        tile.tap(); app.buttons["testSettingsDone"].tap()
        XCTAssertFalse(tile.isSelected)
        tile.tap(); XCTAssertTrue(app.buttons["try-sudoku"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sudoku-difficulty-3"].isSelected)
        XCTAssertTrue(app.buttons["sudoku-timer-240"].isSelected)
        app.buttons["try-sudoku"].tap()
        XCTAssertTrue(app.buttons["exitPractice"].waitForExistence(timeout: 5))
        assertSquareBoard(app, prefix: "sudoku-cell-", size: 6)
        let empty = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sudoku-cell-' AND value CONTAINS 'Empty'")).firstMatch
        XCTAssertTrue(empty.exists); empty.tap()
        app.buttons["sudoku-digit-1"].tap()
        app.buttons["sudokuErase"].tap()
        capture(app, name: "ios-sudoku-practice")
        app.buttons["exitPractice"].tap()
    }

    @MainActor func testMinesHoldChordsAndDoneRequiresExactFlagCount() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-mine-chord"]; app.launch()
        openEditor(app); openTest(app, "mines")
        app.buttons["mine-timer-40"].tap(); app.buttons["try-mines"].tap()
        let cells = app.descendants(matching: .any)
        XCTAssertTrue(cells["mine-cell-17"].waitForExistence(timeout: 5))
        XCTAssertEqual(cells["mine-cell-22"].value as? String, "Hidden")
        cells["mine-cell-17"].press(forDuration: 0.6)
        XCTAssertEqual(cells["mine-cell-17"].value as? String, "Flagged")
        cells["mine-cell-16"].press(forDuration: 0.6)
        XCTAssertNotEqual(cells["mine-cell-22"].value as? String, "Hidden")
        XCTAssertFalse(app.buttons["mineDone"].isEnabled)
        for id in [14, 18, 19] { cells["mine-cell-\(id)"].press(forDuration: 0.6) }
        XCTAssertTrue(app.buttons["mineDone"].isEnabled)
        capture(app, name: "ios-mines-confirm-flags")
        app.buttons["mineDone"].tap()
        XCTAssertTrue(app.buttons["retryPractice"].waitForExistence(timeout: 5))
    }
    @MainActor func testMathOperationsAndSetStateAreExplicit() {
        let app = launch(); openEditor(app); openTest(app, "math")
        XCTAssertEqual(app.buttons["testSettingsDone"].label, "Set")
        for op in ["subtraction", "multiplication", "division"] { app.buttons["math-operation-" + op].tap() }
        app.buttons["closeTestSettings"].tap()
        XCTAssertFalse(app.buttons["test-tile-math"].isSelected)
        openTest(app, "math")
        for op in ["addition", "subtraction", "multiplication", "division"] { XCTAssertTrue(app.buttons["math-operation-" + op].isSelected) }
        app.buttons["testSettingsDone"].tap()
        XCTAssertTrue(app.buttons["test-tile-math"].isSelected)
        openTest(app, "math"); XCTAssertEqual(app.buttons["testSettingsDone"].label, "Unset")
        capture(app, name: "ios-math-four-operations")
    }

    @MainActor func testRingtoneSelectionStaysOpenWithInternalSoundChecker() {
        let app = launch(); openEditor(app)
        let tone = app.buttons.containing(.staticText, identifier: "Classic Beep").firstMatch
        for _ in 0..<5 where !tone.isHittable { scrollEditor(app) }
        XCTAssertFalse(app.buttons["Preview"].exists)
        tone.tap()
        XCTAssertTrue(app.buttons["ringtoneSoundChecker"].waitForExistence(timeout: 5))
        app.buttons["ringtoneSoundChecker"].tap()
        app.buttons["Digital Watch"].tap()
        XCTAssertTrue(app.navigationBars["Ringtone"].exists)
        XCTAssertTrue(app.buttons["Digital Watch"].isSelected)
        capture(app, name: "ios-ringtone-internal-preview")
        app.buttons["ringtoneSoundChecker"].tap()
    }

}
