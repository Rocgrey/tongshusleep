import XCTest

final class SleepAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-compact-preview"]
        app.launch()
    }

    func testDashboardDateAndMetricHelp() {
        XCTAssertTrue(app.staticTexts["sleeptongshu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["示例数据"].exists)
        capture("01-sleep-overview")
        press(app.buttons["上一晚"])
        XCTAssertTrue(app.buttons["下一晚"].isEnabled)
        press(app.buttons["下一晚"])
        press(app.buttons["睡眠参考分说明"])
        XCTAssertTrue(app.staticTexts["睡眠参考分"].waitForExistence(timeout: 3))
        press(app.buttons["关闭说明"])
    }

    func testTrendsAndRecordDetails() {
        selectTab("趋势")
        XCTAssertTrue(app.staticTexts["睡眠趋势"].waitForExistence(timeout: 5))
        capture("02-week-trends")
        press(app.segmentedControls["trendPeriod"].buttons["近 30 天"])
        press(app.segmentedControls["trendMetric"].buttons["效率"])
        XCTAssertTrue(app.staticTexts["30 条记录"].exists)
        capture("03-month-efficiency")
        scrollDown()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "示例数据"))
        press(rows.allElementsBoundByIndex.first { $0.isHittable }!)
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        press(app.buttons["完成"])
    }

    func testManualEntryAndLocalDataManagement() {
        press(app.buttons["addSleep"])
        XCTAssertTrue(app.buttons["saveSleep"].waitForExistence(timeout: 5))
        capture("04-add-record")
        press(app.buttons["saveSleep"])
        selectTab("设备与数据")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "31 条")).firstMatch.waitForExistence(timeout: 5))
        capture("05-device-data")
        scrollDown()
        press(app.buttons["移除示例数据"])
        press(app.buttons.matching(identifier: "移除示例数据").allElementsBoundByIndex.first { $0.isHittable }!)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 条")).firstMatch.waitForExistence(timeout: 5))
        selectTab("睡眠")
        XCTAssertTrue(app.staticTexts["手动记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["手动记录包含睡眠时间，暂无睡眠分期。"].exists)
        capture("06-manual-record")
    }

    func testMonitoringModesAndPhoneReportCharts() {
        selectTab("监测")
        XCTAssertTrue(app.staticTexts["好眠，从今晚开始"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startMonitoring"].isEnabled)
        capture("07-phone-monitoring")
        scrollDown()
        press(app.buttons["previewPhoneReport"])
        XCTAssertTrue(app.staticTexts["模拟数据 · 仅预览，不会保存到睡眠记录"].waitForExistence(timeout: 5))
        capture("08-phone-report")
        press(app.segmentedControls.buttons["体动"])
        capture("09-motion-chart")
        press(app.segmentedControls.buttons["声音事件"])
        capture("10-sound-events")
        press(app.buttons["完成"])
        #if targetEnvironment(macCatalyst)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: 1000)
        #else
        app.swipeDown()
        app.swipeDown()
        #endif
        press(app.segmentedControls["monitorMode"].buttons["穿戴设备"])
        XCTAssertTrue(app.staticTexts["手环、手表与睡眠戒指"].exists)
        capture("11-wearable-monitoring")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func press(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func selectTab(_ title: String) {
        #if targetEnvironment(macCatalyst)
        if app.radioButtons[title].exists { press(app.radioButtons[title]) }
        else { press(app.tabBars.buttons[title]) }
        #else
        press(app.tabBars.buttons[title])
        #endif
    }

    private func scrollDown() {
        #if targetEnvironment(macCatalyst)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
        #else
        app.swipeUp()
        #endif
    }
}
