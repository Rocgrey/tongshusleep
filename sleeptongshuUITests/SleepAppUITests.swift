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
        reveal(app.staticTexts["入睡与醒来的节奏"])
        capture("44-sleep-regularity")
        reveal(app.staticTexts["每日记录"])
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
        XCTAssertTrue(app.staticTexts["监测与设备"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.buttons["connectHealth"].exists)
        XCTAssertFalse(app.staticTexts["从系统健康读取"].exists)
        press(app.segmentedControls["monitorMode"].buttons["设备检测"])
        XCTAssertEqual(app.buttons.matching(identifier: "scanBluetooth").count, 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "搜索蓝牙")).firstMatch.exists)
        XCTAssertFalse(app.buttons["syncVeepooRing"].exists)
        XCTAssertFalse(app.staticTexts["从系统健康读取"].exists)
        press(app.buttons["localData"])
        XCTAssertTrue(app.buttons["导出 JSON 备份"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanBluetooth"].exists)
        capture("12-local-data")
    }

    func testHealthEmptyStateDoesNotInventBodyAgeOrAgingPace() {
        selectTab("健康")
        XCTAssertTrue(app.staticTexts["身体状态"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["readHealthOverview"].exists)
        reveal(app.staticTexts["fitnessAgeValue"])
        XCTAssertEqual(app.staticTexts["fitnessAgeValue"].label, "等待了解你")
        XCTAssertFalse(app.buttons["healthRequestAccess"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "实际年龄未填写")).firstMatch.exists)
        capture("34-health-empty")
        scrollDown()
        XCTAssertFalse(app.buttons["agingPaceHelp"].exists)
    }

    func testHealthRefreshKeepsExistingDataVisibleWhileProgressUpdates() {
        app.terminate()
        app.launchArguments += ["-ui-testing-health", "-ui-testing-health-loading", "-preview-health"]
        app.launch()
        XCTAssertTrue(app.staticTexts["正在更新，已有数据仍可查看"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["healthLatest-steps"].exists)
        XCTAssertTrue(app.buttons["healthLatest-hrv"].exists)
        XCTAssertTrue(app.buttons["fitnessAgeHelp"].exists)
        capture("46-health-refresh-preserves-page")
    }

    func testUnifiedHealthButtonShowsUnchangedResultInlineWithoutAlerts() {
        app.terminate()
        app.launchArguments += ["-ui-testing-health", "-ui-testing-health-refresh-unchanged", "-preview-health"]
        app.launch()
        let read = app.buttons["readHealthOverview"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["healthRequestAccess"].exists)
        press(read)
        let message = app.staticTexts["healthRefreshMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("暂时没有新的数据可以更新"))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.buttons["healthLatest-steps"].exists)
        XCTAssertTrue(app.tabBars.buttons["健康"].exists)
        capture("55-health-unified-no-changes")
    }

    func testHealthOverviewShowsReferenceAgeAndOriginalResearchTitle() {
        launchHealthFixture()
        XCTAssertTrue(app.staticTexts["界面测试示例 · 非真实健康数据"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["fitnessAgeValue"])
        XCTAssertEqual(app.staticTexts["fitnessAgeValue"].label, "约40")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "实验估算，尚未经过验证")).firstMatch.exists)
        scrollDown()
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

    func testHealthReadsAllSourcesWithoutDevicePickers() {
        launchHealthFixture()
        scrollDown()
        scrollDown()
        let steps = app.buttons["healthMetric-steps"]
        reveal(steps)
        XCTAssertTrue(steps.exists)
        capture("39-health-metrics-example")
        press(steps)
        XCTAssertTrue(app.staticTexts["healthDetailValue"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["healthDetailSource"].exists)
        XCTAssertTrue(app.staticTexts["系统健康 · 每日统计"].exists)
        capture("40-health-unified-detail-example")
        reveal(app.staticTexts["哪些天有记录"])
        capture("45-health-record-coverage")
        press(app.buttons["完成"])
        for _ in 0..<10 where !app.buttons["healthSources"].isHittable { app.swipeDown() }
        press(app.buttons["healthSources"])
        XCTAssertTrue(app.navigationBars["健康设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["统一读取系统健康"].exists)
        XCTAssertFalse(app.buttons["healthSource-sleep"].exists)
        XCTAssertFalse(app.buttons["healthSource-steps"].exists)
        capture("41-health-unified-settings-example")
        press(app.buttons["完成"])
    }

    func testHealthOnlyShowsAvailableMetricTiles() {
        app.terminate()
        app.launchArguments += ["-ui-testing-health", "-ui-testing-health-sparse", "-preview-health", "-healthManualProfile", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["readHealthOverview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["healthReadStatus"].label.contains("已读到 17 项"))
        XCTAssertTrue(app.buttons["healthLatest-steps"].exists)
        reveal(app.staticTexts["fitnessAgeValue"])
        XCTAssertEqual(app.staticTexts["fitnessAgeValue"].label, "约40")
        reveal(app.buttons["healthMetric-steps"])
        XCTAssertTrue(app.buttons["healthMetric-steps"].exists)
        XCTAssertFalse(app.buttons["healthMetric-oxygen"].exists)
        XCTAssertFalse(app.buttons["healthMetric-vo2"].exists)
        capture("42-health-available-metrics-example")
    }

    func testHealthAccessGuideExplainsPermissionsAndDeviceWriteRequirement() {
        selectTab("健康")
        press(app.buttons["healthAccessHelp"])
        XCTAssertTrue(app.navigationBars["健康读取指引"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "开启你希望读取的项目")).firstMatch.exists)
        scrollDown()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "只有配套 App 支持且实际写入")).firstMatch.exists)
        reveal(app.buttons["openSystemHealth"])
        capture("43-health-permission-guide")
        press(app.buttons["完成"])
    }

    private func launchHealthFixture() {
        app.terminate()
        app.launchArguments += ["-ui-testing-health", "-preview-health", "-healthManualProfile", "NO"]
        app.launch()
    }

    func testExpandedHealthMetricsAndWorkoutDetails() {
        launchHealthFixture()
        XCTAssertTrue(app.buttons["readHealthOverview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["healthRequestAccess"].exists)
        XCTAssertTrue(app.staticTexts["healthReadStatus"].label.contains("已读到 19 项"))
        reveal(app.buttons["healthMetric-distance"])
        capture("47-health-distance-and-energy")
        press(app.buttons["healthMetric-distance"])
        XCTAssertTrue(app.navigationBars["步行与跑步距离"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["healthDetailValue"].exists)
        press(app.buttons["完成"])
        reveal(app.buttons["healthMetric-weight"])
        capture("48-health-body-measurements")
        reveal(app.buttons["healthMetric-workout"])
        press(app.buttons["healthMetric-workout"])
        XCTAssertTrue(app.navigationBars["体能训练"].waitForExistence(timeout: 3))
        reveal(app.staticTexts["最近的训练"])
        XCTAssertTrue(app.staticTexts["跑步"].exists)
        capture("49-health-workout-details")
        press(app.buttons["完成"])
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

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            scrollDown()
        }
        XCTAssertTrue(element.exists)
    }
}
