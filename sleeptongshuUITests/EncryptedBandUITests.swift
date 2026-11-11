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
    func testCredentialSetupRequiresExplicitDeviceAndDoesNotStartBluetoothOrFakeSync() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-preview-monitor", "-preview-wearable"]
        app.launch()
        let setup = app.buttons["encryptedBandSetup"]
        for _ in 0..<8 where !setup.isHittable { app.swipeUp() }
        XCTAssertTrue(setup.isHittable)
        setup.tap()
        XCTAssertTrue(app.staticTexts["encryptedBandNeedsConnection"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["importBandCredentialFolder"].isEnabled)
        XCTAssertFalse(app.staticTexts["本次文件读取完成"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "encrypted-band-setup-no-device"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["scanBluetooth"].exists)
    }
}
