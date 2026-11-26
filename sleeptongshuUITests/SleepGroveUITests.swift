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
        XCTAssertTrue(app.buttons["noisePlayPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["noiseStop"].isHittable)
        capture(app, "noise")
        app.openGroveSection("掌心安睡仪")
        for _ in 0..<6 where !app.buttons["productIntroductionVideo"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["productIntroductionVideo"].waitForExistence(timeout: 5))
        capture(app, "product-introduction")
        for _ in 0..<8 where !app.buttons["productImage-jd-sleep-device"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["productImage-jd-sleep-device"].waitForExistence(timeout: 5))
        capture(app, "product")
        app.openGroveSection("用户中心")
        XCTAssertTrue(app.buttons["enhancedSettings"].waitForExistence(timeout: 5))
        capture(app, "center")
    }
    func testPSQICompletesAndAllTwentyFourSoundsAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-light"]
        app.launch()
        app.openGroveSection("科普")
        app.segmentedControls["classroomSections"].buttons["自测"].tap()
        XCTAssertFalse(app.staticTexts["已有 AIS 自评"].exists)
        app.buttons["grovePSQI"].tap()
        app.buttons["startPSQI"].tap()
        let questionIDs = ["q1", "q2", "q3", "q4", "q5a", "q5b", "q5c", "q5d", "q5e", "q5f", "q5g", "q5h", "q5i", "q5j", "q6", "q7", "q8", "q9"]
        for question in 0..<18 {
            XCTAssertTrue(app.otherElements["psqiArtwork-" + questionIDs[question]].waitForExistence(timeout: 5))
            if [0, 5, 17].contains(question) { capture(app, "psqi-cartoon-" + questionIDs[question]) }
            if question == 1 || question == 3 {
                let field = app.textFields["psqiNumber"]
                for _ in 0..<4 where !field.isHittable { app.swipeUp() }
                field.tap(); field.typeText(question == 1 ? "35" : "6.5")
                app.buttons["完成输入"].tap()
            } else if question >= 4 {
                let option = question == 4 || question == 5 ? 2 : question == 15 ? 0 : 1
                let answer = app.buttons["psqiOption\(option)"]
                for _ in 0..<4 where !answer.isHittable || answer.frame.maxY >= app.buttons["psqiNext"].frame.minY - 8 { app.swipeUp() }
                answer.tap()
            }
            let next = app.buttons["psqiNext"]
            for _ in 0..<3 where !next.isHittable { app.swipeUp() }
            next.tap()
        }
        XCTAssertTrue(app.navigationBars["这次自测"].waitForExistence(timeout: 5))
        capture(app, "psqi-result-test-answers")
        let history = app.otherElements["psqiHistoryComparison"]
        for _ in 0..<6 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.exists)
        capture(app, "psqi-history-test-answers")
        let advisor = app.descendants(matching: .any).matching(identifier: "psqiAdvisor").firstMatch
        for _ in 0..<12 where !advisor.isHittable { app.swipeUp() }
        XCTAssertTrue(advisor.isHittable)
        capture(app, "psqi-advisor-test-answers")
        app.openGroveSection("助眠")
        for _ in 0..<4 where !app.buttons["groveNoise"].isHittable { app.swipeUp() }
        app.buttons["groveNoise"].tap()
        XCTAssertTrue(app.buttons["noisePlayPause"].isHittable)
        for sound in 0..<24 {
            let tile = app.buttons["noise-\(sound)"]
            for _ in 0..<12 where !tile.isHittable { app.swipeUp() }
            XCTAssertTrue(tile.isHittable, "Sound \(sound) is reachable")
        }
        capture(app, "noise-final-presets")
        app.buttons["noise-23"].tap()
        for _ in 0..<14 where !app.buttons["noiseStop"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["正在陪伴你"].waitForExistence(timeout: 8))
        capture(app, "noise-playing-selected-preset")
        app.buttons["noiseStop"].tap()
        XCTAssertTrue(app.staticTexts["留一点安静给自己"].exists)
    }
    func testPSQICartoonSupportsDarkLargeTextAndBackNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        app.openGroveSection("科普")
        app.segmentedControls["classroomSections"].buttons["自测"].tap()
        let entry = app.buttons["grovePSQI"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let start = app.buttons["startPSQI"]
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.otherElements["psqiArtwork-q1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["psqiNext"].isHittable)
        capture(app, "psqi-cartoon-dark-large")
        app.buttons["psqiNext"].tap()
        XCTAssertTrue(app.otherElements["psqiArtwork-q2"].waitForExistence(timeout: 5))
        app.buttons["上一项"].tap()
        XCTAssertTrue(app.otherElements["psqiArtwork-q1"].waitForExistence(timeout: 5))
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
    func testColorfulHealthAgeRetainsActualAgeAndTestSourceLabel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-health", "-ui-testing-health-sparse", "-ui-testing-light"]
        app.launch()
        app.openGroveSection("健康")
        let value = app.staticTexts["fitnessAgeValue"]
        for _ in 0..<10 where !value.isHittable { app.swipeUp() }
        XCTAssertTrue(value.isHittable)
        XCTAssertTrue(app.staticTexts["实际年龄 42 岁"].exists)
        capture(app, "health-age-synthetic-data")
    }
}
