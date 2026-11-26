import XCTest

final class SleepGroveUITests: XCTestCase {
    func testTemperatureChartUsesOnlyLabeledDeviceTestSamples() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-vitals", "-ui-testing-light"]
        app.launch()
        app.openGroveSection("监测与设备")
        app.segmentedControls["monitorMode"].buttons["设备检测"].tap()
        let entry = app.buttons["wearableVitals"]
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["vitalMetricMenu"].tap()
        app.buttons["体温"].tap()
        XCTAssertTrue(app.otherElements["wearableVitalTimeline"].exists)
        capture(app, "temperature-chart-synthetic-data")
        XCTAssertTrue(app.staticTexts["体温"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "sleepgrove-test-" + name; image.lifetime = .keepAlways; add(image)
    }
    func testFiveTabsAndExistingFeaturesRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-theme", "-ui-testing-light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["SleepGrove"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertTrue(app.staticTexts["示例数据"].exists)
        XCTAssertTrue(app.otherElements["sleepStageTimeline"].exists)
        capture(app, "home-synthetic-data")
        app.buttons["上一晚"].tap(); app.buttons["下一晚"].tap()
        app.openGroveSection("监测与设备")
        XCTAssertTrue(app.segmentedControls["monitorMode"].waitForExistence(timeout: 5))
        capture(app, "monitoring")
        app.openGroveSection("趋势")
        XCTAssertTrue(app.segmentedControls["trendCategory"].waitForExistence(timeout: 5))
        capture(app, "trends-synthetic-data")
        app.openGroveSection("健康")
        XCTAssertTrue(app.buttons["readHealthOverview"].waitForExistence(timeout: 5))
        capture(app, "health-not-yet-read")
        app.openGroveSection("科普")
        XCTAssertTrue(app.segmentedControls["classroomSections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["classroomSections"].buttons["产品"].exists)
        capture(app, "learn-bundled-content")
        app.openGroveSection("助眠")
        capture(app, "relax")
        for _ in 0..<4 where !app.buttons["groveBreathing"].isHittable { app.swipeUp() }
        app.buttons["groveBreathing"].tap()
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 5))
        app.buttons["开始"].tap(); XCTAssertTrue(app.buttons["暂停"].exists)
        app.buttons["暂停"].tap()
        capture(app, "breathing-visual")
        for _ in 0..<4 where !app.buttons["previewBreathingCue"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["previewBreathingCue"].isHittable)
        app.buttons["previewBreathingCue"].tap()
        capture(app, "breathing")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["groveNoise"].tap()
        XCTAssertTrue(app.buttons["groveNoiseSelection"].waitForExistence(timeout: 5))
        capture(app, "noise")
        app.openGroveSection("掌心安睡仪")
        XCTAssertTrue(app.buttons["productIntroductionVideo"].waitForExistence(timeout: 5))
        capture(app, "product-introduction")
        for _ in 0..<8 where !app.buttons["productImage-jd-sleep-device"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["productImage-jd-sleep-device"].waitForExistence(timeout: 5))
        capture(app, "product")
        app.openGroveSection("用户中心")
        XCTAssertTrue(app.buttons["enhancedSettings"].waitForExistence(timeout: 5))
        capture(app, "center")
    }
    func testDarkLargeTypeAndNotificationRelaxRoute() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL", "-ui-testing-notification-route", "goodnight"]
        app.launch()
        XCTAssertTrue(app.navigationBars["晚安"].waitForExistence(timeout: 10))
        capture(app, "dark-large-goodnight")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.tabBars.buttons["助眠"].isSelected)
        app.openGroveSection("科普")
        capture(app, "dark-large-learn")
        app.openGroveSection("用户中心")
        app.buttons["enhancedSettings"].tap()
        app.buttons["外观"].tap()
        app.buttons["theme-cute"].tap()
        XCTAssertEqual(app.buttons["theme-cute"].value as? String, "已选择")
        capture(app, "dark-large-theme")
    }
}
