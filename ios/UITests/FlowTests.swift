import XCTest

/// Drives the real app against the local backend. The host shell moves the
/// simulated GPS location while the run test cruises.
final class FlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Home → prerun → run (~2.5 min of simulated movement) → hold-to-finish
    /// → summary → collect → home.
    func testRunLoop() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DEV_AUTOLOGIN_PHONE"] = "0901112233"
        app.launch()

        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bắt đầu'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "home start button")
        start.tap()

        let runToggle = app.staticTexts["Chạy bộ"]
        XCTAssertTrue(runToggle.waitForExistence(timeout: 10), "type toggle")
        runToggle.tap()

        let begin = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bắt đầu chạy'")).firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 40), "GPS ready begin button")
        begin.tap()

        XCTAssertTrue(app.staticTexts["Quãng đường · km"].waitForExistence(timeout: 15), "run screen")

        // Cruise while the host moves the location northward.
        Thread.sleep(forTimeInterval: 150)

        let hold = app.otherElements["finishHold"]
        XCTAssertTrue(hold.exists, "hold control")
        hold.press(forDuration: 3.6)

        let collect = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nhận'")).firstMatch
        XCTAssertTrue(collect.waitForExistence(timeout: 20), "summary collect button")
        Thread.sleep(forTimeInterval: 4) // screenshot window for the host
        collect.tap()

        XCTAssertTrue(app.staticTexts["Điểm hôm nay"].waitForExistence(timeout: 15), "back home")
        Thread.sleep(forTimeInterval: 4)
    }

    /// Rewards → redeem 20K voucher → voucher screen with barcode.
    /// Uses a seeded user with balance; Guardian link done host-side.
    func testRedeemVoucher() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DEV_AUTOLOGIN_PHONE"] = "0977777777"
        app.launch()

        let rewardsTab = app.staticTexts["Thưởng"]
        XCTAssertTrue(rewardsTab.waitForExistence(timeout: 20), "tab bar")
        rewardsTab.tap()

        let redeemButton = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS '10.000'")
        ).firstMatch
        XCTAssertTrue(redeemButton.waitForExistence(timeout: 15), "20K voucher card")
        Thread.sleep(forTimeInterval: 3) // rewards screenshot window
        redeemButton.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Xác nhận'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "redeem sheet")
        Thread.sleep(forTimeInterval: 3) // sheet screenshot window
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Đưa màn hình này cho thu ngân"].waitForExistence(timeout: 20),
            "voucher screen"
        )
        Thread.sleep(forTimeInterval: 5) // voucher screenshot window
    }
}
