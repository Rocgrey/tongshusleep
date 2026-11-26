import XCTest

extension XCUIApplication {
    /// Legacy feature tests enter the same screens through the new home shortcuts.
    func openGroveSection(_ title: String) {
        let close = buttons["closeGroveModule"]
        if close.exists { close.tap() }
        let module = ["健康": "health", "趋势": "trends", "监测与设备": "monitoring"][title]
        if let module {
            tabBars.buttons["睡眠"].tap()
            let shortcut = buttons["grove-" + module]
            for _ in 0..<4 where !shortcut.isHittable { swipeDown() }
            for _ in 0..<12 where !shortcut.isHittable { swipeUp() }
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
            shortcut.tap()
        } else {
            tabBars.buttons[title == "睡眠课堂" ? "科普" : title].tap()
        }
    }
}
