import XCTest

final class AccountUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-account", "-ui-testing-account-service", "-compact-preview"]
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
    private func enterLogin(password: String = "test-pass-only") {
        let email = app.textFields["accountEmail"]
        if (email.value as? String)?.contains("@") != true {
            show(email); email.tap(); email.typeText("sleeper@example.com\n")
        }
        let input = app.secureTextFields["accountPassword"]
        show(input); input.tap(); input.typeText(password + "\n")
        show(app.buttons["accountSubmit"])
        app.buttons["accountSubmit"].tap()
    }
    func testRegisterReturnsToEmailLoginThenProfileAndLogoutWork() {
        capture("60-email-login")
        XCTAssertTrue(app.switches["accountRemember"].exists)
        XCTAssertFalse(app.buttons["accountPreview"].exists)
        app.segmentedControls["accountMode"].buttons["注册"].tap()
        let username = app.textFields["accountUsername"]
        username.tap(); username.typeText("sleeper_test\n")
        let email = app.textFields["accountEmail"]
        show(email); email.tap(); email.typeText("sleeper@example.com\n")
        let password = app.secureTextFields["accountPassword"]
        show(password); password.tap(); password.typeText("test-pass-only\n")
        let confirm = app.secureTextFields["accountConfirmPassword"]
        show(confirm); confirm.tap(); confirm.typeText("test-pass-only\n")
        show(app.buttons["accountSubmit"]); capture("61-register-form")
        app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.switches["accountRemember"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
        enterLogin()
        XCTAssertTrue(app.tabBars.buttons["健康"].waitForExistence(timeout: 5))
        app.tabBars.buttons["健康"].tap()
        app.buttons["openAccount"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "sleeper@example.com")).firstMatch.waitForExistence(timeout: 5))
        capture("62-account-profile")
        app.buttons["accountSignOut"].tap()
        app.buttons["确定退出"].tap()
        XCTAssertTrue(app.segmentedControls["accountMode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
    }
    func testWrongPasswordDisplaysBackendMessageAndStaysLoggedOut() {
        enterLogin(password: "wrongpass")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["邮箱或密码不正确"].exists)
        capture("63-login-server-error")
        app.alerts.buttons["知道了"].tap()
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
    }
    func testUploadReviewUsesCurrentAccountAndPreservesOptionalQuestionnaires() {
        enterLogin()
        XCTAssertTrue(app.buttons["addSleep"].waitForExistence(timeout: 5))
        app.buttons["addSleep"].tap()
        XCTAssertTrue(app.buttons["saveSleep"].waitForExistence(timeout: 5))
        app.buttons["saveSleep"].tap()
        let upload = app.buttons["openSleepUpload"]
        show(upload); upload.tap()
        XCTAssertTrue(app.textFields["uploadISI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["uploadAIS"].exists)
        XCTAssertTrue(app.buttons["submitSleepUpload"].exists)
        XCTAssertTrue(app.staticTexts["sleeper@example.com"].exists)
        capture("64-sleep-upload-review")
    }
    func testInvalidEmailShowsValidationWithoutEnteringApp() {
        app.textFields["accountEmail"].tap()
        app.textFields["accountEmail"].typeText("invalid\n")
        let password = app.secureTextFields["accountPassword"]
        show(password); password.tap(); password.typeText("test-pass-only\n")
        show(app.buttons["accountSubmit"]); app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["请填写完整的邮箱地址。"].exists)
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
    }
}
