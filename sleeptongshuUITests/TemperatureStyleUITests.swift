import XCTest

final class TemperatureStyleUITests: XCTestCase {
    func testHomeTemperatureAndDetailSelectionUseTheSameTestReadings() {
        continueAfterFailure = false
        let app = launch(dark: false)
        let trend = app.staticTexts["体温趋势"].firstMatch
        for _ in 0..<12 where !trend.isHittable { app.swipeUp() }
        XCTAssertTrue(trend.isHittable)
        XCTAssertTrue(app.staticTexts["界面测试示例 · 非真实数据"].exists)
        screenshot(app, "temperature-home-light-test-data")
        app.openGroveSection("监测与设备")
        app.segmentedControls["monitorMode"].buttons["设备检测"].tap()
        let entry = app.buttons["wearableVitals"]
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["vitalMetricMenu"].tap(); app.buttons["体温"].tap()
        // The same chart remains behind the sheet on home; scope controls to the visible module.
        let detail = app.otherElements["groveModuleSurface"]
        XCTAssertTrue(detail.staticTexts["体温趋势"].waitForExistence(timeout: 5))
        let plot = detail.descendants(matching: .any).matching(identifier: "temperatureRangeChart").firstMatch
        for _ in 0..<6 where !plot.isHittable { app.swipeUp() }
        screenshot(app, "temperature-chart-light-test-data")
        let previous = detail.buttons["previousTemperatureDay"]
        for _ in 0..<6 where !previous.isHittable { app.swipeUp() }
        let selected = detail.descendants(matching: .any).matching(identifier: "temperatureSelectedDay").firstMatch
        let before = selected.label
        previous.tap()
        XCTAssertNotEqual(selected.label, before)
        XCTAssertTrue(detail.buttons["nextTemperatureDay"].isEnabled)
        detail.buttons["nextTemperatureDay"].tap()
        XCTAssertEqual(selected.label, before)
        screenshot(app, "temperature-detail-light-test-data")
        for _ in 0..<6 where !app.segmentedControls["vitalPeriod"].isHittable { app.swipeDown() }
        app.segmentedControls["vitalPeriod"].buttons["近 30 天"].tap()
        XCTAssertTrue(detail.staticTexts["体温趋势"].exists)
    }

    func testDarkLargeTypeRetainsTemperatureControlsAndAllThemes() {
        continueAfterFailure = false
        let app = launch(dark: true)
        app.openGroveSection("监测与设备")
        app.segmentedControls["monitorMode"].buttons["设备检测"].tap()
        let entry = app.buttons["wearableVitals"]
        for _ in 0..<10 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let menu = app.buttons["vitalMetricMenu"]
        for _ in 0..<6 where !menu.isHittable { app.swipeUp() }
        menu.tap(); app.buttons["体温"].tap()
        let detail = app.otherElements["groveModuleSurface"]
        let plot = detail.descendants(matching: .any).matching(identifier: "temperatureRangeChart").firstMatch
        for _ in 0..<12 where !plot.isHittable { app.swipeUp() }
        screenshot(app, "temperature-chart-dark-large-test-data")
        let previous = detail.buttons["previousTemperatureDay"]
        for _ in 0..<12 where !previous.isHittable { app.swipeUp() }
        if !previous.isHittable {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "temperature-test-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
            screenshot(app, "temperature-controls-failure-test-data")
        }
        XCTAssertTrue(previous.isHittable)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        XCTAssertGreaterThanOrEqual(previous.frame.width, 44)
        previous.tap()
        XCTAssertTrue(detail.buttons["nextTemperatureDay"].isEnabled)
        screenshot(app, "temperature-dark-accessibility-test-data")
        app.openGroveSection("用户中心")
        let settings = app.buttons["enhancedSettings"]
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        settings.tap(); app.buttons["外观"].tap()
        for theme in ["business", "fresh", "cute"] {
            app.buttons["theme-" + theme].tap()
            XCTAssertEqual(app.buttons["theme-" + theme].value as? String, "已选择")
        }
        screenshot(app, "appearance-dark-accessibility")
    }

    private func launch(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-vitals", "-ui-testing-reset-theme", dark ? "-ui-testing-dark" : "-ui-testing-light"]
        if dark { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
