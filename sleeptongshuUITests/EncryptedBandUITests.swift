import XCTest

final class EncryptedBandUITests: XCTestCase {
    func testIntermediateBIOReportExplainsUnqueriedChannels() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-probe", "-ui-testing-probe-incomplete", "-preview-monitor", "-preview-wearable"]
        app.launch()
        let report = app.buttons["wearableProbeReport"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap() // XCTest scrolls to this short row; full-page swipes can skip it on SE.
        let notice = app.descendants(matching: .any).matching(identifier: "incompleteWearableProbe").firstMatch
        for _ in 0..<5 where !notice.isHittable { app.swipeUp() }
        XCTAssertTrue(notice.exists)
        XCTAssertTrue(notice.label.contains("没有读取结束标记"))
    }
    func testDevicePageNoLongerExposesCredentialImport() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-preview-monitor", "-preview-wearable"]
        app.launch()
        XCTAssertTrue(app.buttons["scanBluetooth"].waitForExistence(timeout: 5))
        for _ in 0..<5 {
            XCTAssertFalse(app.buttons["encryptedBandSetup"].exists)
            XCTAssertFalse(app.buttons["importBandCredentialFolder"].exists)
            XCTAssertFalse(app.staticTexts["导入设备绑定凭证"].exists)
            app.swipeUp()
        }
        for _ in 0..<5 where !app.buttons["scanBluetooth"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["scanBluetooth"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "device-page-without-credential-import"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
