import XCTest

final class SleepClassroomUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
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

    func testDarkLargeTypeNativeClassroomAndUnavailableProducts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL", "-ui-testing-dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["睡眠课堂"].waitForExistence(timeout: 10))
        app.tabBars.buttons["睡眠课堂"].tap()
        XCTAssertTrue(app.segmentedControls["classroomSections"].waitForExistence(timeout: 5))
        capture(app, "dark-large-type")
        app.segmentedControls["classroomSections"].buttons["产品"].tap()
        XCTAssertTrue(app.staticTexts["商品信息核实后会在这里展示"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
