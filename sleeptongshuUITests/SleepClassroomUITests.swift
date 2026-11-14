import XCTest

final class SleepClassroomUITests: XCTestCase {
    /// This smoke test intentionally visits the real classroom website; it requires network access.
    func testLiveClassroomLoadsAndRemainsAvailableAfterTabSwitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let classroom = app.tabBars.buttons["睡眠课堂"]
        XCTAssertTrue(classroom.waitForExistence(timeout: 8))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        classroom.tap()
        XCTAssertTrue(app.navigationBars["睡眠课堂"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        let headline = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "夜深了")).firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["classroomReload"].exists)
        app.buttons["classroomOptions"].tap()
        XCTAssertTrue(app.buttons["课堂首页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["在浏览器中打开"].exists)
        app.buttons["课堂首页"].tap()
        XCTAssertTrue(headline.waitForExistence(timeout: 30))
        let enterWebsite = app.webViews.buttons["进入官网"]
        if enterWebsite.waitForExistence(timeout: 3), enterWebsite.isHittable { enterWebsite.tap() }
        XCTAssertTrue(headline.isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "sleep-classroom-live-compact"; image.lifetime = .keepAlways; add(image)
        app.tabBars.buttons["睡眠"].tap()
        XCTAssertTrue(app.segmentedControls["sleepDashboardSource"].waitForExistence(timeout: 5))
        classroom.tap()
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
    }
}
