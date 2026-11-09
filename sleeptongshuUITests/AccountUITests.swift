import XCTest
import UIKit

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
        app.segmentedControls["accountLoginMethod"].buttons["邮箱"].tap()
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
        XCTAssertTrue(app.alerts.staticTexts["账号或密码错误"].exists)
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
        XCTAssertTrue(app.textFields["uploadAIS"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["uploadISI"].exists)
        XCTAssertTrue(app.buttons["submitSleepUpload"].exists)
        XCTAssertTrue(app.staticTexts["sleeper@example.com"].exists)
        capture("64-sleep-upload-review")
    }
    func testInvalidEmailShowsValidationWithoutEnteringApp() {
        app.segmentedControls["accountLoginMethod"].buttons["邮箱"].tap()
        app.textFields["accountEmail"].tap()
        app.textFields["accountEmail"].typeText("invalid\n")
        let password = app.secureTextFields["accountPassword"]
        show(password); password.tap(); password.typeText("test-pass-only\n")
        show(app.buttons["accountSubmit"]); app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["请填写完整的邮箱地址。"].exists)
        XCTAssertFalse(app.tabBars.buttons["健康"].exists)
    }
    func testPhoneRegistrationWithoutEmailThenProfileAndStepSources() {
        capture("70-phone-login")
        app.segmentedControls["accountMode"].buttons["注册"].tap()
        let username = app.textFields["accountUsername"]
        username.tap(); username.typeText("phone_test\n")
        let phone = app.textFields["accountPhone"]
        show(phone); phone.tap(); phone.typeText("13800001234")
        app.buttons["accountKeyboardDone"].tap()
        let password = app.secureTextFields["accountPassword"]
        show(password); password.tap(); password.typeText("test-pass-only\n")
        let confirm = app.secureTextFields["accountConfirmPassword"]
        show(confirm); confirm.tap(); confirm.typeText("test-pass-only\n")
        show(app.buttons["accountSubmit"]); capture("71-phone-register")
        app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.switches["accountRemember"].waitForExistence(timeout: 5))
        let loginPassword = app.secureTextFields["accountPassword"]
        show(loginPassword); loginPassword.tap(); loginPassword.typeText("test-pass-only\n")
        show(app.buttons["accountSubmit"]); app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.tabBars.buttons["趋势"].waitForExistence(timeout: 5))
        app.tabBars.buttons["趋势"].tap()
        app.segmentedControls["trendCategory"].buttons["步数"].tap()
        XCTAssertTrue(app.segmentedControls["stepsSource"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚未读取账号步数"].exists)
        capture("72-account-steps-empty")
        app.segmentedControls["stepsSource"].buttons["本机系统健康"].tap()
        XCTAssertTrue(app.staticTexts["尚未读取这段时间的系统步数"].exists)
        app.tabBars.buttons["健康"].tap(); app.buttons["openAccount"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "13800001234")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["邮箱"].exists)
        capture("73-phone-profile")
    }
    func testStepChartKeepsMissingDatesAndZeroSeparateAcrossPeriods() {
        app.terminate()
        app.launchArguments.append("-ui-testing-steps-chart")
        app.launch()
        enterLogin()
        XCTAssertTrue(app.tabBars.buttons["趋势"].waitForExistence(timeout: 5))
        app.tabBars.buttons["趋势"].tap()
        app.segmentedControls["trendCategory"].buttons["步数"].tap()
        XCTAssertTrue(app.otherElements["stepsChart"].waitForExistence(timeout: 5))
        assertStepBarsRender()
        capture("74-steps-week-chart")
        app.segmentedControls["trendPeriod"].buttons["近 30 天"].tap()
        XCTAssertTrue(app.staticTexts["有记录 22 天 · 其中 0 步 1 天 · 未记录 8 天"].waitForExistence(timeout: 5))
        assertStepBarsRender()
        capture("75-steps-month-chart")
    }
    private func assertStepBarsRender(file: StaticString = #filePath, line: UInt = #line) {
        guard let image = app.otherElements["stepsChart"].screenshot().image.cgImage else { return XCTFail("Chart screenshot missing", file: file, line: line) }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let count = pixels.withUnsafeMutableBytes { buffer -> Int in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            // Teal is used only for bars inside the captured plot, not axes or text.
            return stride(from: 0, to: buffer.count, by: 4).filter {
                bytes[$0] < 65 && bytes[$0 + 1] > 80 && bytes[$0 + 1] < 160 && bytes[$0 + 2] > 65 && bytes[$0 + 2] < 150
            }.count
        }
        XCTAssertGreaterThan(count, 500, "The chart must draw visible bars, not only axes", file: file, line: line)
    }
}
