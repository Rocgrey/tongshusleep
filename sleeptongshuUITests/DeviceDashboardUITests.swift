import XCTest

final class DeviceDashboardUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-bio"]
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testBIOShowsStepsAndVitalsWithoutHealthReadOrInventedSleep() {
        app.launch()
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].buttons["设备记录"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].buttons["设备记录"].isSelected)
        XCTAssertTrue(app.buttons["openDeviceSteps"].exists)
        XCTAssertFalse(app.otherElements["sleepStageTimeline"].exists)
        XCTAssertFalse(app.staticTexts["systemSleepReadAt"].exists)
        reveal(app.staticTexts["暂无设备睡眠记录"])
        capture("device-sleep-empty-with-real-input-boundary-synthetic")
        reveal(app.staticTexts["设备最近体征"])
        XCTAssertTrue(app.staticTexts["设备最近体征"].exists)
        capture("device-recent-vitals-synthetic")
        app.tabBars.buttons["趋势"].tap()
        app.segmentedControls["trendCategory"].buttons["步数"].tap()
        XCTAssertTrue(app.segmentedControls["stepsSource"].buttons["蓝牙设备"].isSelected)
        XCTAssertTrue(app.otherElements["stepsChart"].exists)
        capture("device-seven-day-steps-synthetic")
        app.segmentedControls["trendPeriod"].buttons["近 30 天"].tap()
        XCTAssertTrue(app.otherElements["stepsChart"].exists)
        capture("device-thirty-day-steps-synthetic")
    }
    func testDeviceSleepShowsImmediatelyAndExplicitSourceChoiceIsPreserved() {
        app.launchArguments += ["-ui-testing-device-sleep", "-ui-testing-system-sleep", "-system-sleep-empty"]
        app.launch()
        let source = app.segmentedControls["sleepDashboardSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(source.buttons["设备记录"].isSelected)
        reveal(app.otherElements["sleepStageTimeline"])
        XCTAssertTrue(app.otherElements["sleepStageTimeline"].exists)
        capture("device-sleep-timeline-synthetic")
        for _ in 0..<10 where !source.isHittable { app.swipeDown() }
        source.buttons["系统健康"].tap()
        app.buttons["readHealthOverview"].tap()
        XCTAssertTrue(app.staticTexts["systemSleepReadAt"].waitForExistence(timeout: 8))
        XCTAssertTrue(source.buttons["系统健康"].isSelected)
        source.buttons["设备记录"].tap()
        XCTAssertTrue(source.buttons["设备记录"].isSelected)
        reveal(app.otherElements["sleepStageTimeline"])
        XCTAssertTrue(app.otherElements["sleepStageTimeline"].exists)
    }
}
