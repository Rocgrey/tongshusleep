import XCTest

final class SleepClassroomUITests: XCTestCase {
    func testPublishedLiveContentEndToEndWhenExplicitInspectionFixtureExists() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("work/private-v043-live/catalog.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Live deployment inspection was not requested") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        let rows = try XCTUnwrap(json["items"] as? [[String: Any]])
        let course = try XCTUnwrap(rows.first { ($0["id"] as? String)?.hasPrefix("verify-course-") == true })
        let product = try XCTUnwrap(rows.first { ($0["id"] as? String)?.hasPrefix("verify-prod-") == true })
        let article = try XCTUnwrap(rows.first { ($0["id"] as? String)?.hasPrefix("v043-status-") == true })
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-live-content", "-ui-testing-light"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["睡眠课堂"].waitForExistence(timeout: 10)); app.tabBars.buttons["睡眠课堂"].tap()
        XCTAssertTrue(app.staticTexts["classroomUpdatedAt"].waitForExistence(timeout: 30))
        let card = app.buttons["classroomItem-" + (course["id"] as! String)]
        for _ in 0..<4 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.exists)
        capture(app, "live-published-courses")
        app.buttons["refreshClassroom"].tap()
        app.segmentedControls["classroomSections"].buttons["产品"].tap()
        let productImage = app.buttons["productImage-" + (product["id"] as! String)]
        for _ in 0..<4 where !productImage.isHittable { app.swipeUp() }
        XCTAssertTrue(productImage.exists)
        capture(app, "live-published-products")
        for _ in 0..<4 where !app.segmentedControls["classroomSections"].isHittable { app.swipeDown() }
        app.segmentedControls["classroomSections"].buttons["阅读"].tap()
        XCTAssertTrue(app.staticTexts[article["title"] as! String].waitForExistence(timeout: 10))
        capture(app, "live-published-articles")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        // App screenshots can crop a programmatically rotated scene to portrait bounds.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "enhanced-test-" + name; image.lifetime = .keepAlways; add(image)
    }
    func testNativeClassroomReadingBreathingAndThemes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-compact-preview", "-ui-testing-reset-theme", "-ui-testing-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let classroom = app.tabBars.buttons["睡眠课堂"]
        XCTAssertTrue(classroom.waitForExistence(timeout: 10)); classroom.tap()
        XCTAssertTrue(app.segmentedControls["classroomSections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        capture(app, "native-courses")
        app.segmentedControls["classroomSections"].buttons["阅读"].tap()
        capture(app, "native-articles")
        app.segmentedControls["classroomSections"].buttons["助眠"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "4-7-8 呼吸")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["4-7-8 呼吸"].waitForExistence(timeout: 5))
        app.buttons["开始"].tap(); XCTAssertTrue(app.buttons["暂停"].exists)
        app.buttons["暂停"].tap(); capture(app, "breathing")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["enhancedSettings"].tap()
        app.buttons["外观"].tap()
        for theme in ["business", "cute", "fresh"] {
            let button = app.buttons["theme-"+theme]
            button.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已选择"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 4), .completed)
            capture(app, "theme-"+theme)
        }
    }

    func testDarkLargeTypeNativeClassroomAndVerifiedProduct() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL", "-ui-testing-dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["睡眠课堂"].waitForExistence(timeout: 10))
        app.tabBars.buttons["睡眠课堂"].tap()
        XCTAssertTrue(app.segmentedControls["classroomSections"].waitForExistence(timeout: 5))
        capture(app, "dark-large-type")
        app.segmentedControls["classroomSections"].buttons["产品"].tap()
        XCTAssertTrue(app.buttons["productImage-jd-sleep-device"].exists)
        capture(app, "verified-jd-product-dark")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testFullCourseLabelsProductAndFastTabNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-theme", "-ui-testing-light"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["睡眠课堂"].waitForExistence(timeout: 10))
        for (index, tab) in ["睡眠课堂", "健康", "趋势", "监测与设备", "睡眠", "睡眠课堂"].enumerated() {
            app.tabBars.buttons[tab].tap()
            capture(app, "preview-style-tab-\(index)")
        }
        let course = app.descendants(matching: .any).matching(identifier: "classroomItem-insomnia-course").firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5)); course.tap()
        XCTAssertTrue(app.navigationBars["课程播放"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["横屏播放"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "试看")).firstMatch.exists)
        capture(app, "full-course-player")
        let nextChapter = app.buttons["playLesson-course-l2"]
        if !nextChapter.isHittable { app.swipeUp() }
        XCTAssertTrue(nextChapter.waitForExistence(timeout: 5)); nextChapter.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "当前播放"), object: nextChapter)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        capture(app, "selected-second-chapter")
        app.buttons["横屏播放"].tap()
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["classroomLandscapeSurface"].waitForExistence(timeout: 5))
        // Geometry changes before UIKit's rotation animation has finished.
        let rotationFinished = expectation(description: "Landscape animation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { rotationFinished.fulfill() }
        wait(for: [rotationFinished], timeout: 3)
        capture(app, "landscape-player")
        app.buttons["退出横屏"].tap()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        app.buttons["完成"].tap()
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
        app.segmentedControls["classroomSections"].buttons["产品"].tap()
        XCTAssertTrue(app.buttons["productImage-jd-sleep-device"].exists)
        capture(app, "verified-jd-product")
    }
}
