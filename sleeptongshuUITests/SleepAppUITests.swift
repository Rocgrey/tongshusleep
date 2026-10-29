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
        XCTAssertTrue(app.staticTexts["睡眠参考分怎么算？"].waitForExistence(timeout: 3))
        press(app.buttons["关闭说明"])
    }

    func testSleepEfficiencyAndStageReferencesAreAccessible() {
        press(app.buttons["睡眠效率说明"])
        XCTAssertTrue(app.staticTexts["睡眠效率怎么算？"].waitForExistence(timeout: 3))
        capture("17-efficiency-explanation")
        press(app.buttons["关闭说明"])
        scrollDown()
        let rem = app.buttons["快速眼动参考范围"]
        if !rem.isHittable { scrollDown() }
        press(rem)
        XCTAssertTrue(app.staticTexts["快速眼动占比"].waitForExistence(timeout: 3))
        capture("18-rem-explanation")
        press(app.buttons["关闭说明"])
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "平均呼吸率")).firstMatch.exists)
        capture("19-sleep-stages-and-references")
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
        selectTab("监测与设备")
        press(app.buttons["localData"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "31 条")).firstMatch.waitForExistence(timeout: 5))
        capture("05-device-data")
        scrollDown()
        press(app.buttons["移除示例数据"])
        press(app.buttons.matching(identifier: "移除示例数据").allElementsBoundByIndex.first { $0.isHittable }!)
        #if targetEnvironment(macCatalyst)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: 1000)
        #else
        app.swipeDown()
        app.swipeDown()
        #endif
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 条")).firstMatch.waitForExistence(timeout: 5))
        selectTab("睡眠")
        XCTAssertTrue(app.staticTexts["手动记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["手动记录包含睡眠时间，暂无睡眠分期。"].exists)
        capture("06-manual-record")
    }

    func testMonitoringModesAndPhoneReportCharts() {
        selectTab("监测与设备")
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
        press(app.segmentedControls["monitorMode"].buttons["戒指监测"])
        XCTAssertTrue(app.staticTexts["睡眠戒指"].exists)
        capture("11-wearable-monitoring")
    }

    func testUnifiedDeviceAndDataNavigationHasOneScanner() {
        selectTab("监测与设备")
        XCTAssertFalse(app.tabBars.buttons["设备与数据"].exists)
        press(app.segmentedControls["monitorMode"].buttons["戒指监测"])
        XCTAssertEqual(app.buttons.matching(identifier: "scanRing").count, 1)
        XCTAssertFalse(app.buttons["syncVeepooRing"].exists)
        press(app.buttons["localData"])
        XCTAssertTrue(app.buttons["导出 JSON 备份"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanRing"].exists)
        capture("12-local-data")
    }

    func testWearableVitalsEmptyStateDoesNotInventMeasurements() {
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["戒指监测"])
        XCTAssertFalse(app.staticTexts["戒指睡眠同步 · 测试"].exists)
        press(app.buttons["wearableVitals"])
        XCTAssertTrue(app.staticTexts["暂无体征记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["HRV（设备值）"].exists)
        capture("13-vitals-empty")
    }

    func testWearableVitalsChartsUseAvailableMetricsOnly() {
        app.terminate()
        app.launchArguments += ["-ui-testing-vitals"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["戒指监测"])
        capture("14-wearable-device-page")
        press(app.buttons["wearableVitals"])
        XCTAssertTrue(app.buttons["查看血氧趋势"].waitForExistence(timeout: 5))
        press(app.buttons["查看血氧趋势"])
        XCTAssertFalse(app.staticTexts["血糖（设备估计）"].exists)
        capture("15-vitals-oxygen-chart")
        press(app.buttons["查看HRV（设备值）趋势"])
        capture("16-vitals-hrv-chart")
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
