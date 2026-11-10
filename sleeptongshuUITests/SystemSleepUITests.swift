import XCTest

final class SystemSleepUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-system-sleep"]
    }

    func testHealthSleepReadUpdatesDashboardAndRepeatedRefreshKeepsSevenRecords() {
        app.launchArguments += ["-preview-health"]
        app.launch()
        readSleep()
        app.tabBars.buttons["睡眠"].tap()
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].buttons["系统健康"].isSelected)
        reveal(app.staticTexts["界面测试来源 · 非真实健康数据"])
        XCTAssertTrue(app.staticTexts["界面测试来源 · 非真实健康数据"].exists)
        XCTAssertFalse(app.buttons["睡眠参考分说明"].exists)
        capture("system-sleep-overview-test-data")
        reveal(app.otherElements["sleepStageTimeline"])
        let timeline = app.otherElements["sleepStageTimeline"]
        XCTAssertTrue(timeline.exists)
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["阶段详情"].waitForExistence(timeout: 5))
        capture("system-sleep-stage-detail-test-data")
        app.buttons["完成"].tap()
        for _ in 0..<8 where !app.buttons["readHealthOverview"].isHittable { app.swipeDown() }
        readSleep()
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.staticTexts["6 条记录"].waitForExistence(timeout: 5))
        capture("system-sleep-seven-days-test-data")
        app.segmentedControls["trendPeriod"].buttons["近 30 天"].tap()
        XCTAssertTrue(app.staticTexts["7 条记录"].exists)
        capture("system-sleep-thirty-days-test-data")
    }

    func testNoRecordsShowsEmptyStateWithoutDemoAfterImport() {
        app.launchArguments += ["-system-sleep-empty"]
        app.launch()
        readSleep()
        reveal(app.staticTexts["暂无系统睡眠"])
        XCTAssertTrue(app.staticTexts["暂无系统睡眠"].exists)
        XCTAssertFalse(app.staticTexts["示例数据"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未读取到睡眠记录，请检查系统健康中的数据和访问设置")).firstMatch.exists)
        capture("system-sleep-empty-test-state")
    }

    func testBedOnlyDoesNotShowSleepDurationOrStageChart() {
        app.launchArguments += ["-system-sleep-bed-only"]
        app.launch()
        readSleep()
        reveal(app.staticTexts["仅有卧床记录"])
        XCTAssertTrue(app.staticTexts["仅有卧床记录"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-bed-only-test-data")
    }

    func testUnspecifiedSleepIsNotPresentedAsCore() {
        app.launchArguments += ["-system-sleep-unspecified"]
        app.launch()
        readSleep()
        reveal(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "未分期睡眠 ·")).firstMatch)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "未分期睡眠 ·")).firstMatch.exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-unspecified-test-data")
    }

    func testLargeTypeKeepsReadEntryAndSourceDetailsReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        readSleep()
        reveal(app.staticTexts["界面测试来源 · 非真实健康数据"])
        capture("system-sleep-large-type-test-data")
        reveal(app.otherElements["sleepStageTimeline"])
        XCTAssertTrue(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-large-type-stages-test-data")
    }

    func testUnifiedHealthReadSeparatesBedOnlyAndOpensLatestConfirmedSleep() {
        app.launchArguments += ["-system-sleep-mixed", "-preview-health"]
        app.launch()
        readSleep()
        reveal(app.staticTexts["latestConfirmedSystemSleep"])
        XCTAssertTrue(app.staticTexts["latestConfirmedSystemSleep"].label.contains("8小时0分"))
        XCTAssertTrue(app.staticTexts["systemSleepMessage"].label.contains("5 段睡眠记录，另有 2 段仅卧床记录"))
        reveal(app.staticTexts["latestSystemBedRecord"])
        XCTAssertTrue(app.staticTexts["latestSystemBedRecord"].exists)
        capture("unified-health-sleep-summary-test-data")
        app.tabBars.buttons["睡眠"].tap()
        let duration = app.descendants(matching: .any).matching(identifier: "totalSleepDuration").firstMatch
        reveal(duration)
        XCTAssertEqual(duration.label, "8小时0分")
        XCTAssertFalse(app.buttons["readSystemSleep"].exists)
        capture("latest-confirmed-sleep-before-bed-only-test-data")
    }

    private func readSleep() {
        let button = app.buttons["readHealthOverview"]
        reveal(button)
        XCTAssertEqual(app.buttons.matching(identifier: "readHealthOverview").count, 1)
        XCTAssertFalse(app.buttons["readSystemSleep"].exists)
        XCTAssertFalse(app.buttons["读取系统睡眠"].exists)
        button.tap()
        XCTAssertTrue(app.staticTexts["systemSleepReadAt"].waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.staticTexts["systemSleepMessage"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
