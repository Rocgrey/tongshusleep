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
        XCTAssertEqual(app.links.count, 0)
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
        XCTAssertTrue(app.staticTexts["Danielle Pacheco"].exists)
        XCTAssertTrue(app.staticTexts["原文：How Much Deep Sleep Do You Need?"].exists)
        XCTAssertEqual(app.links.count, 0)
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
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertTrue(app.staticTexts["睡眠设备"].exists)
        capture("11-wearable-monitoring")
    }

    func testUnifiedDeviceAndDataNavigationHasOneScanner() {
        selectTab("监测与设备")
        XCTAssertFalse(app.tabBars.buttons["设备与数据"].exists)
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertEqual(app.buttons.matching(identifier: "scanBluetooth").count, 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "搜索蓝牙")).firstMatch.exists)
        XCTAssertFalse(app.buttons["syncVeepooRing"].exists)
        press(app.buttons["localData"])
        XCTAssertTrue(app.buttons["导出 JSON 备份"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanBluetooth"].exists)
        capture("12-local-data")
    }

    func testHealthEmptyStateDoesNotInventBodyAgeOrAgingPace() {
        selectTab("健康")
        XCTAssertTrue(app.staticTexts["身体状态"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["readHealthOverview"].exists)
        XCTAssertEqual(app.staticTexts["fitnessAgeValue"].label, "—")
        capture("34-health-empty")
        scrollDown()
        let agingHelp = app.buttons["agingPaceHelp"]
        if !agingHelp.isHittable { scrollDown() }
        press(agingHelp)
        XCTAssertTrue(app.staticTexts["能看出衰老速度吗？"].waitForExistence(timeout: 3))
        capture("35-aging-limits")
        press(app.buttons["关闭说明"])
    }

    func testHealthOverviewShowsReferenceAgeAndOriginalResearchTitle() {
        launchHealthFixture()
        XCTAssertTrue(app.staticTexts["界面测试示例 · 非真实健康数据"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fitnessAgeValue"].label, "约40")
        capture("36-health-overview-example")
        press(app.buttons["fitnessAgeHelp"])
        XCTAssertTrue(app.staticTexts["身体年龄参考怎么算？"].waitForExistence(timeout: 3))
        scrollDown()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reference Standards for Cardiorespiratory Fitness")).firstMatch.exists)
        XCTAssertEqual(app.links.count, 0)
        capture("37-fitness-age-method-example")
        press(app.buttons["关闭说明"])
        scrollDown()
        capture("38-health-change-and-recovery-example")
    }

    func testHealthSourceSwitchKeepsDifferentDevicesSeparate() {
        launchHealthFixture()
        scrollDown()
        scrollDown()
        let steps = app.buttons["healthMetric-steps"]
        for _ in 0..<4 where !steps.isHittable { scrollDown() }
        XCTAssertTrue(steps.exists)
        capture("39-health-metrics-example")
        press(steps)
        XCTAssertTrue(app.staticTexts["healthDetailValue"].waitForExistence(timeout: 3))
        let before = app.staticTexts["healthDetailValue"].label
        press(app.buttons["healthDetailSource"])
        let ring = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "戒指 B")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 3))
        press(ring)
        XCTAssertNotEqual(app.staticTexts["healthDetailValue"].label, before)
        capture("40-health-device-comparison-example")
        press(app.buttons["完成"])
        press(app.buttons["healthSources"])
        XCTAssertTrue(app.navigationBars["来源与参考资料"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["healthSource-sleep"].exists)
        XCTAssertTrue(app.buttons["healthSource-steps"].exists)
        capture("41-health-source-selection-example")
        press(app.buttons["完成"])
    }

    private func launchHealthFixture() {
        app.terminate()
        app.launchArguments += ["-ui-testing-health", "-preview-health", "-healthManualProfile", "NO"]
        app.launch()
    }

    func testNewWearableReportSeparatesReadingsFromUnknownCapabilities() {
        app.terminate()
        app.launchArguments += ["-ui-testing-probe", "-preview-monitor", "-preview-wearable"]
        app.launch()
        XCTAssertTrue(app.staticTexts["设备数据接入"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["7/9 格"].exists)
        XCTAssertTrue(app.staticTexts["4312"].exists)
        capture("30-wearable-probe-overview-example")
        let report = app.buttons["wearableProbeReport"]
        if !report.isHittable { scrollDown() }
        press(report)
        XCTAssertTrue(app.navigationBars["设备接入报告"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["实际返回固件"].exists)
        XCTAssertTrue(app.staticTexts["用户提供的版本"].exists)
        capture("31-wearable-probe-report-example")
        scrollDown()
        XCTAssertTrue(app.staticTexts["查询未响应，尚不能确认支持情况"].exists)
        capture("32-wearable-probe-channels-example")
        scrollDown()
        capture("33-wearable-probe-history-example")
        press(app.buttons["完成"])
    }

    func testWearableVitalsEmptyStateDoesNotInventMeasurements() {
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertFalse(app.staticTexts["戒指睡眠同步 · 测试"].exists)
        press(app.buttons["wearableVitals"])
        XCTAssertTrue(app.staticTexts["暂无体征记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["HRV"].exists)
        capture("13-vitals-empty")
    }

    func testValidationReportShowsUncertaintyAndInventsNoWaveform() {
        app.terminate()
        app.launchArguments += ["-ui-testing-validation"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        openDeviceDiagnostics()
        press(app.buttons["deviceValidationReport"])
        XCTAssertTrue(app.staticTexts["界面测试示例"].waitForExistence(timeout: 5))
        capture("24-validation-interface-results")
        press(app.segmentedControls["validationSections"].buttons["信号图"])
        XCTAssertTrue(app.staticTexts["暂无信号可画"].waitForExistence(timeout: 3))
        capture("25-validation-no-signals")
        press(app.segmentedControls["validationSections"].buttons["全部字段"])
        XCTAssertTrue(app.staticTexts["history.ppgs"].waitForExistence(timeout: 3))
        capture("26-validation-fields")
        press(app.buttons["完成"])
    }

    func testValidationCandidateGraphRetainsUnconfirmedUnits() {
        app.terminate()
        app.launchArguments += ["-ui-testing-validation", "-validation-signals"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        openDeviceDiagnostics()
        press(app.buttons["deviceValidationReport"])
        XCTAssertTrue(app.staticTexts["界面测试示例"].waitForExistence(timeout: 5))
        press(app.segmentedControls["validationSections"].buttons["信号图"])
        XCTAssertTrue(app.staticTexts["逐次心跳的候选数据"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不代表毫秒")).firstMatch.exists)
        capture("27-validation-candidate-graph")
        press(app.buttons["完成"])
    }

    func testEverydaySyncKeepsDiagnosticsCollapsedAndValidationOffAfterRelaunch() {
        app.terminate()
        app.launchArguments += ["-deviceSignalValidationEnabled", "YES"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertTrue(app.buttons["scanBluetooth"].exists)
        XCTAssertFalse(app.switches["enableDeviceValidation"].exists)
        XCTAssertFalse(app.buttons["deviceValidationReport"].exists)
        capture("28-everyday-device-page")
        openDeviceDiagnostics()
        let toggle = app.switches["enableDeviceValidation"]
        XCTAssertEqual(toggle.value as? String, "0")
        press(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        capture("29-device-diagnostics")
        app.terminate()
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        openDeviceDiagnostics()
        XCTAssertEqual(app.switches["enableDeviceValidation"].value as? String, "0")
    }

    func testDeviceBatteryPercentageAndDisconnectedReadingAreVisible() {
        app.terminate()
        app.launchArguments += ["-ui-testing-battery"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertTrue(app.staticTexts["deviceBatteryValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["deviceBatteryValue"].label, "68%")
        XCTAssertTrue(app.staticTexts["最近读取的电量"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "当前已断开")).firstMatch.exists)
        capture("22-device-battery-percentage")
    }

    func testDeviceBatteryGridDoesNotInventAPercentage() {
        app.terminate()
        app.launchArguments += ["-ui-testing-battery", "-battery-grid"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertTrue(app.staticTexts["deviceBatteryValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["deviceBatteryValue"].label, "3/4 格")
        XCTAssertTrue(app.staticTexts["设备只提供电量格数，暂不显示百分比。"].exists)
        capture("23-device-battery-grid")
    }

    func testWearableVitalsChartsUseAvailableMetricsOnly() {
        app.terminate()
        app.launchArguments += ["-ui-testing-vitals"]
        app.launch()
        selectTab("监测与设备")
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        capture("14-wearable-device-page")
        press(app.buttons["wearableVitals"])
        XCTAssertTrue(app.buttons["查看血氧趋势"].waitForExistence(timeout: 5))
        press(app.buttons["查看血氧趋势"])
        XCTAssertFalse(app.staticTexts["已隐藏项目"].exists)
        capture("15-vitals-oxygen-chart")
        scrollDown()
        if !app.staticTexts["每天的高低变化"].isHittable { scrollDown() }
        XCTAssertTrue(app.staticTexts["每天的高低变化"].exists)
        capture("20-vitals-daily-range")
        scrollDown()
        if !app.staticTexts["哪些数值出现得多"].isHittable { scrollDown() }
        XCTAssertTrue(app.staticTexts["哪些数值出现得多"].exists)
        capture("21-vitals-distribution")
        #if targetEnvironment(macCatalyst)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: 2500)
        #else
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        #endif
        press(app.buttons["查看HRV趋势"])
        capture("16-vitals-hrv-chart")
    }

    private func openDeviceDiagnostics() {
        let entry = app.buttons["设备诊断"].firstMatch
        for _ in 0..<4 {
            if entry.isHittable { break }
            scrollDown()
        }
        press(entry)
        scrollDown()
        XCTAssertTrue(app.buttons["deviceValidationReport"].waitForExistence(timeout: 3))
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
