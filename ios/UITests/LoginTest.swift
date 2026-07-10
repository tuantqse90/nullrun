import XCTest

/// Reproduces the manual phone-login path the founder hit on device:
/// tap "Dùng số điện thoại", type a number, request OTP.
final class LoginTest: XCTestCase {
    func testPhoneEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DEV_FORCE_LOGOUT"] = "1"
        app.launch()

        let usePhone = app.buttons["Dùng số điện thoại"]
        XCTAssertTrue(usePhone.waitForExistence(timeout: 20), "landing")
        usePhone.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "phone field")
        field.tap()
        field.typeText("0939317968")
        Thread.sleep(forTimeInterval: 2) // screenshot window: did it go blank?

        let send = app.buttons["Nhận mã OTP"]
        XCTAssertTrue(send.exists, "send button present after typing")
        send.tap()

        let codeField = app.textFields.firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 15), "reached code step")
        Thread.sleep(forTimeInterval: 2)
    }
}
