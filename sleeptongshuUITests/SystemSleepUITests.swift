import XCTest

final class SystemSleepUITests: XCTestCase {
    private var app: XCUIApplication!
    private var displayed: XCUIElement {
        let close = app.buttons["closeGroveModule"]
        return close.exists && close.isHittable ? app.otherElements["groveModuleSurface"] : app
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-system-sleep"]
    }

    func testHealthSleepReadUpdatesDashboardAndRepeatedRefreshKeepsSevenRecords() {
        app.launchArguments += ["-preview-health"]
        app.launch()
        readSleep()
        app.openGroveSection("睡眠")
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].buttons["系统健康"].isSelected)
        let source = displayed.staticTexts["systemSleepSourceName"]
        reveal(source)
        XCTAssertTrue(source.label.contains("界面测试来源"))
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
        app.openGroveSection("趋势")
        XCTAssertTrue(displayed.staticTexts["6 条记录"].waitForExistence(timeout: 5))
        capture("system-sleep-seven-days-test-data")
        app.segmentedControls["trendPeriod"].buttons["近 30 天"].tap()
        XCTAssertTrue(displayed.staticTexts["7 条记录"].exists)
        capture("system-sleep-thirty-days-test-data")
    }

    func testNoRecordsShowsEmptyStateWithoutDemoAfterImport() {
        app.launchArguments += ["-system-sleep-empty"]
        app.launch()
        readSleep()
        reveal(displayed.staticTexts["暂无系统睡眠"])
        XCTAssertTrue(displayed.staticTexts["暂无系统睡眠"].exists)
        XCTAssertFalse(displayed.staticTexts["示例数据"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        XCTAssertTrue(displayed.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未读取到睡眠记录，请检查系统健康中的数据和访问设置")).firstMatch.exists)
        capture("system-sleep-empty-test-state")
    }

    func testBedOnlyDoesNotShowSleepDurationOrStageChart() {
        app.launchArguments += ["-system-sleep-bed-only"]
        app.launch()
        readSleep()
        reveal(displayed.staticTexts["仅有卧床记录"])
        XCTAssertTrue(displayed.staticTexts["仅有卧床记录"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-bed-only-test-data")
    }

    func testUnspecifiedSleepIsNotPresentedAsCore() {
        app.launchArguments += ["-system-sleep-unspecified"]
        app.launch()
        readSleep()
        reveal(displayed.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "未分期睡眠 ·")).firstMatch)
        XCTAssertTrue(displayed.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "未分期睡眠 ·")).firstMatch.exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-unspecified-test-data")
    }

    func testLargeTypeKeepsReadEntryAndSourceDetailsReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        readSleep()
        reveal(displayed.staticTexts["systemSleepSourceName"])
        capture("system-sleep-large-type-test-data")
        reveal(app.otherElements["sleepStageTimeline"])
        XCTAssertTrue(app.otherElements["sleepStageTimeline"].exists)
        capture("system-sleep-large-type-stages-test-data")
    }

    func testUnifiedHealthReadSeparatesBedOnlyAndOpensLatestConfirmedSleep() {
        app.launchArguments += ["-system-sleep-mixed", "-preview-health"]
        app.launch()
        readSleep()
        reveal(displayed.staticTexts["latestConfirmedSystemSleep"])
        XCTAssertTrue(displayed.staticTexts["latestConfirmedSystemSleep"].label.contains("8小时0分"))
        XCTAssertTrue(displayed.staticTexts["systemSleepMessage"].label.contains("5 段睡眠记录，另有 2 段仅卧床记录"))
        reveal(displayed.staticTexts["latestSystemBedRecord"])
        XCTAssertTrue(displayed.staticTexts["latestSystemBedRecord"].exists)
        capture("unified-health-sleep-summary-test-data")
        app.openGroveSection("睡眠")
        let duration = app.descendants(matching: .any).matching(identifier: "totalSleepDuration").firstMatch
        reveal(duration)
        XCTAssertEqual(duration.label, "8小时0分")
        XCTAssertFalse(app.buttons["readSystemSleep"].exists)
        capture("latest-confirmed-sleep-before-bed-only-test-data")
    }

    private func readSleep() {
        if !app.buttons["closeGroveModule"].exists {
            app.openGroveSection("健康")
        }
        let surface = app.otherElements["groveModuleSurface"]
        let button = surface.buttons["readHealthOverview"]
        reveal(button)
        XCTAssertEqual(surface.buttons.matching(identifier: "readHealthOverview").count, 1)
        XCTAssertFalse(app.buttons["readSystemSleep"].exists)
        XCTAssertFalse(app.buttons["读取系统睡眠"].exists)
        button.tap()
        XCTAssertTrue(displayed.staticTexts["systemSleepReadAt"].waitForExistence(timeout: 8))
        expectation(for: NSPredicate { _, _ in button.isEnabled }, evaluatedWith: button)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(displayed.staticTexts["systemSleepMessage"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        if !app.launchArguments.contains("-preview-health") {
            app.openGroveSection("睡眠")
            app.segmentedControls["sleepDashboardSource"].buttons["系统健康"].tap()
        }
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        }
        if !element.exists { capture("unreachable-health-element") }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable, "Element should be visible after scrolling")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
