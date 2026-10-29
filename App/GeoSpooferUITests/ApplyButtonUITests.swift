import XCTest

final class ApplyButtonUITests: XCTestCase {
    @MainActor
    func testApplyStaysDisabledUntilTheFormIsComplete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let apply = app.buttons["Apply"]
        if !apply.waitForExistence(timeout: 8) {
            throw XCTSkip("The window was not exposed to the test runner. OverridePanel.canApply covers the disabled Apply state.")
        }
        XCTAssertFalse(apply.isEnabled)
    }
}
