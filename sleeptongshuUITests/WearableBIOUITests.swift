import XCTest

final class WearableBIOUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["查看血压高压趋势"].exists)
        app.buttons["查看HRV趋势"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这里显示设备给出的 SDNN")).firstMatch.exists)
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
