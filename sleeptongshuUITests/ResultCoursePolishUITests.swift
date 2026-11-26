import XCTest

final class ResultCoursePolishUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "sleepgrove-v054-test-" + name; image.lifetime = .keepAlways; add(image)
    }
    func testEveryPublishedChapterHasAnEntryAndProductFullscreenReturns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-theme", "-ui-testing-light"]
        app.launch()
        app.openGroveSection("科普")
        for id in ["course-l1", "course-l2", "course-l3", "course-l4", "course-l5", "cbti-video", "sleep-harm-video"] {
            let lesson = app.buttons["classroomLesson-" + id]
            for _ in 0..<12 where !lesson.isHittable { app.swipeUp() }
            XCTAssertTrue(lesson.isHittable, "Published chapter \(id) is visible")
            if ["course-l1", "course-l5", "sleep-harm-video"].contains(id) { capture(app, "course-" + id) }
        }
        app.openGroveSection("掌心安睡仪")
        let expand = app.buttons["productVideoFullscreen"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["productIntroductionVideo"].exists)
        capture(app, "inline-product-cover")
        expand.tap()
        XCTAssertTrue(app.navigationBars["产品介绍"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["横屏播放"].exists)
        capture(app, "fullscreen-product-cover")
        app.buttons["横屏播放"].tap()
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        app.buttons["完成"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
    }
    func testDarkLargeTextChaptersAndGentleVoiceControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        app.openGroveSection("科普")
        let lesson = app.buttons["classroomLesson-course-l1"]
        for _ in 0..<10 where !lesson.isHittable { app.swipeUp() }
        XCTAssertTrue(lesson.isHittable)
        capture(app, "chapters-dark-large")
        app.openGroveSection("助眠")
        let breathing = app.buttons["groveBreathing"]
        for _ in 0..<8 where !breathing.isHittable { app.swipeUp() }
        breathing.tap()
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 5))
        app.swipeUp()
        capture(app, "voice-dark-large")
        app.openGroveSection("掌心安睡仪")
        let fullscreen = app.buttons["productVideoFullscreen"]
        for _ in 0..<12 where !fullscreen.isHittable { app.swipeUp() }
        XCTAssertTrue(fullscreen.isHittable)
        capture(app, "product-dark-large")
    }
}
