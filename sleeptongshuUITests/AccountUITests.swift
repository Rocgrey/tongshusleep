import XCTest

final class AccountUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    private func launch(configured: Bool) {
        app.launchArguments = ["-ui-testing", "-ui-testing-account", "-compact-preview"]
        if configured { app.launchArguments.append("-ui-testing-account-service") }
        app.launch()
        XCTAssertTrue(app.segmentedControls["accountMode"].waitForExistence(timeout: 5))
    }
    private func show(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable && element.frame.maxY < app.windows.firstMatch.frame.maxY - 60 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testUnconfiguredServiceShowsHonestPreviewWithoutRegistering() {
        launch(configured: false)
        XCTAssertTrue(app.staticTexts["accountNotConfigured"].exists)
        capture("50-account-login-unconfigured")
        app.segmentedControls["accountMode"].buttons["注册"].tap()
        XCTAssertTrue(app.secureTextFields["accountConfirmPassword"].exists)
        show(app.buttons["accountSubmit"])
        XCTAssertFalse(app.buttons["accountSubmit"].isEnabled)
        capture("51-account-register-unconfigured")
        for _ in 0..<4 where !app.buttons["accountPreview"].isHittable { app.swipeDown() }
        app.buttons["accountPreview"].tap()
        capture("52-account-after-preview")
        XCTAssertTrue(app.tabBars.buttons["健康"].waitForExistence(timeout: 5))
        app.tabBars.buttons["健康"].tap()
        app.buttons["openAccount"].tap()
        XCTAssertTrue(app.staticTexts["本机预览 · 尚未登录或注册"].waitForExistence(timeout: 5))
        capture("52-account-preview-center")
    }

    func testConfiguredRegistrationEntersAppAndSignOutReturnsToLogin() {
        launch(configured: true)
        XCTAssertFalse(app.buttons["accountPreview"].exists)
        app.segmentedControls["accountMode"].buttons["注册"].tap()
        let username = app.textFields["accountUsername"]
        username.tap()
        username.typeText("sleeper_test")
        app.buttons["accountKeyboardDone"].tap()
        let password = app.secureTextFields["accountPassword"]
        show(password); password.tap(); password.typeText("test-pass-only")
        password.typeText("\n")
        let confirmation = app.secureTextFields["accountConfirmPassword"]
        show(confirmation); confirmation.tap(); confirmation.typeText("test-pass-only")
        confirmation.typeText("\n")
        let nickname = app.textFields["accountDisplayName"]
        show(nickname); nickname.tap(); nickname.typeText("Sleep Test")
        app.buttons["accountKeyboardDone"].tap()
        capture("53-account-filled-test-form")
        show(app.buttons["accountSubmit"])
        app.buttons["accountSubmit"].tap()
        let entered = app.tabBars.buttons["健康"].waitForExistence(timeout: 8)
        capture("53-account-after-test-submit")
        XCTAssertTrue(entered)
        app.tabBars.buttons["健康"].tap()
        app.buttons["openAccount"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "sleeper_test")).firstMatch.waitForExistence(timeout: 5))
        capture("53-account-test-session-center")
        app.buttons["accountSignOut"].tap()
        app.buttons["确定退出"].tap()
        XCTAssertTrue(app.segmentedControls["accountMode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
    }

    func testWrongPasswordStaysInlineWithoutAnAlert() {
        launch(configured: true)
        let username = app.textFields["accountUsername"]
        username.tap(); username.typeText("sleeper_test")
        app.buttons["accountKeyboardDone"].tap()
        let password = app.secureTextFields["accountPassword"]
        password.tap(); password.typeText("wrongpass\n")
        show(app.buttons["accountSubmit"])
        app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.staticTexts["accountMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["accountMessage"].label.contains("账号或密码不正确"))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
        capture("54-account-inline-error")
    }
}
