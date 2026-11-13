//
//  DeepLinkUITests.swift
//  CosmicPathSwiftUITests
//
//  Issue #33: the Custom Product Pages' deep links open their scenario, both
//  when the app is not running (cold) and when it is (warm). iOS asks
//  "Open in …?" for a custom scheme, so the test confirms that alert.
//

import XCTest

final class DeepLinkUITests: XCTestCase {

    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Cold launch

    @MainActor
    func testColdLinkOpensPlanetScenario() throws {
        terminateAfterFirstLaunch()
        try openLink("cosmicpath://scenario/black-hole/planet")
        try expectRunning(showing: "1 s = 10 min")
    }

    @MainActor
    func testColdLinkIgnoresCase() throws {
        terminateAfterFirstLaunch()
        try openLink("COSMICPATH://Scenario/Black-Hole/S2/")
        try expectRunning(showing: "S2 around Sgr A*")
    }

    @MainActor
    func testColdUnknownLinkOpensAppNormally() throws {
        terminateAfterFirstLaunch()
        try openLink("cosmicpath://scenario/black-hole/wormhole")
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: timeout), "app should open paused, as usual")
        XCTAssertFalse(app.buttons["Pause"].exists)
    }

    // MARK: - Warm

    @MainActor
    func testWarmLinksSwitchScenario() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: timeout))

        try openLink("cosmicpath://scenario/three-body/figure-8")
        try expectRunning(showing: "Bound")

        try openLink("cosmicpath://scenario/black-hole/s2")
        try expectRunning(showing: "S2 around Sgr A*")
    }

    // MARK: - Helpers

    /// Cold start: a clone simulator only gets the app installed on its first
    /// launch, so launch once (registering the URL scheme), then quit.
    @MainActor
    private func terminateAfterFirstLaunch() {
        app.launch()
        app.terminate()
    }

    /// Opens `link` from the system and confirms the "Open in …?" alert.
    @MainActor
    private func openLink(_ link: String) throws {
        let url = try XCTUnwrap(URL(string: link))
        XCUIDevice.shared.system.open(url)
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 5) {
            openButton.tap()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "\(link) should bring the app forward")
    }

    /// The scenario is running (Pause shown) and some element's label or value
    /// contains `text` (the scale badge keeps its text in the value).
    @MainActor
    private func expectRunning(showing text: String) throws {
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: timeout), "scenario should be running")
        let label = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: timeout), "expected an element showing \"\(text)\"")
    }
}
