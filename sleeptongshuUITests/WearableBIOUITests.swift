import XCTest

final class WearableBIOUITests: XCTestCase {
    func testDenseBIONightsSwitchDatesAndReuseStageCharts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-device-sleep", "-ui-testing-dense-bio", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        let date = app.buttons["选择睡眠日期"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let first = date.value as? String
        let before = Date.now
        for _ in 0..<3 {
            let previous = date.value as? String ?? ""
            app.buttons["上一晚"].tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previous), object: date)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        print("Synthetic dense BIO / three date taps including UI automation: \(Date.now.timeIntervalSince(before))s")
        for _ in 0..<3 { app.buttons["下一晚"].tap() }
        XCTAssertEqual(date.value as? String, first)
        let chart = app.descendants(matching: .any).matching(identifier: "sleepStageTimeline").firstMatch
        for _ in 0..<8 where !chart.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(chart.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "bio-date-switch-synthetic-1000-readings-96-stages"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testRawSensorsAreSeparateAndCorrectlyNamed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-bio", "-ui-testing-raw-sensors", "-preview-monitor", "-preview-wearable"]
        app.launch()
        XCTAssertTrue(app.staticTexts["rawSensorAutomatic"].waitForExistence(timeout: 6))
        app.buttons["wearableProbeReport"].tap()
        let chart = app.descendants(matching: .any).matching(identifier: "rawSensorChart").firstMatch
        for _ in 0..<15 where !chart.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(chart.isHittable)
        let picker = app.buttons["rawSensorPicker"]
        XCTAssertTrue(picker.exists); picker.tap()
        let bioz = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "BIOZ")).firstMatch
        XCTAssertTrue(bioz.waitForExistence(timeout: 3)); bioz.tap()
        XCTAssertTrue(app.staticTexts["原始信号界面测试示例 · 非真实采集"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "raw-sensors-synthetic-compact-dark"; shot.lifetime = .keepAlways; add(shot)
    }
    private func verifyNight(largeText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-bio", "-ui-testing-bio-night"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].buttons["设备记录"].waitForExistence(timeout: 8))
        let title = app.staticTexts["先看已有的真实记录"]
        for _ in 0..<12 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(app.buttons["openSleepUpload"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        let chart = app.descendants(matching: .any).matching(identifier: "bioNightChart").firstMatch
        for _ in 0..<15 where !chart.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(chart.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = largeText ? "bio-night-synthetic-large-text" : "bio-night-synthetic-small-dark"
        shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bioNightMetric").firstMatch.exists)
    }
    func testNightObservationChartWithoutInventedSleep() { verifyNight(largeText: false) }
    func testNightObservationSupportsAccessibilityText() { verifyNight(largeText: true) }
    func testVitalsOpenOnCurrentBIOInsteadOfAnotherDevicesNewerRecord() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-bio", "-ui-testing-vitals", "-preview-monitor", "-preview-wearable"]
        app.launch()
        let vitals = app.buttons["wearableVitals"]
        XCTAssertTrue(vitals.waitForExistence(timeout: 5)); vitals.tap()
        XCTAssertTrue(app.navigationBars["体征记录"].waitForExistence(timeout: 5))
        let picker = app.buttons["vitalDevicePicker"]
        XCTAssertTrue(picker.label.contains("BIO"))
        app.buttons["vitalMetricMenu"].tap()
        XCTAssertTrue(app.buttons["血压高压"].exists)
        app.buttons["HRV"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这里显示设备给出的 SDNN")).firstMatch
        for _ in 0..<8 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "bio-vitals-current-device-synthetic"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testBIOPercentageBatteryAndDecodedHealthOnSmallScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-bio", "-preview-monitor", "-preview-wearable"]
        app.launch()
        XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["100/9 格"].exists)
        let report = app.buttons["wearableProbeReport"]
        XCTAssertTrue(report.exists); report.tap()
        XCTAssertTrue(app.navigationBars["设备接入报告"].waitForExistence(timeout: 5))
        let title = app.staticTexts["已读取的体征"]
        for _ in 0..<10 where !title.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(title.isHittable)
        let hrv = app.descendants(matching: .any).matching(identifier: "wearableMetric-HRV · SDNN").firstMatch
        for _ in 0..<5 where !hrv.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(hrv.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "bio-decoded-health-synthetic-dark-compact"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.staticTexts["BIO · 界面测试示例"].exists)
    }
}
