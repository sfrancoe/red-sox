import XCTest

/// Uses a loopback fixture only. A single installed binary discovers another story and rolls back.
final class StoryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var origin: String!
    override func setUpWithError() throws {
        continueAfterFailure = false
        origin = try XCTUnwrap(ProcessInfo.processInfo.environment["HUB_UI_STORY_ROOT"])
        XCTAssertTrue(origin.hasPrefix("http://127.0.0.1:"))
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment["HUB_STORY_ROOT"] = origin + "/data"
        app.launchEnvironment["HUB_API_ROOT"] = origin
        app.launchEnvironment["HUB_DATA_ROOT"] = origin + "/data"
        app.launchEnvironment["HUB_STORY_CACHE_NAME"] = "ui-" + name.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(50) + UUID().uuidString.lowercased().prefix(8)
    }
    override func tearDownWithError() throws { app.terminate() }
    private func fixture(_ action: String) async throws {
        let (_, response) = try await URLSession.shared.data(from: URL(string: origin + "/__fixture/" + action)!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    private func launch(size: String = "UICTContentSizeCategoryL", reduced: Bool = false) {
        app.launchArguments = ["-hubCompletedTeamOnboarding", "YES", "-hubSelectedTeam", "rays", "-show-story-library",
                               "-UIPreferredContentSizeCategoryName", size]
        if reduced { app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["stories.refresh"].waitForExistence(timeout: 10))
    }
    private func shot(_ label: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = label + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func reveal(_ element: XCUIElement, attempts: Int = 25) {
        for _ in 0..<attempts {
            if element.exists && (element.isHittable || element.elementType == .other) && element.frame.midY > app.frame.minY + 95 && element.frame.midY < app.frame.maxY - 35 { return }
            let down = element.exists && element.frame.midY < app.frame.minY + 95
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: down ? 0.3 : 0.75))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: down ? 0.75 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not reveal \(element.identifier)")
    }
    private func openFirst() {
        let card = app.buttons["stories.remote.this-stadium"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); reveal(card); card.tap()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout: 10))
    }

    @MainActor func testRemoteStoryGuessPassportAndSources() async throws {
        try await fixture("reset"); launch(); shot("01-library")
        openFirst(); shot("02-two-ball-guess")
        let choice = app.buttons["remote.choice.ball-a"]; reveal(choice); choice.tap()
        XCTAssertTrue(app.staticTexts["remote.answer"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["remote.answer"]); shot("03-shorter-homer-reveal")
        let passport = app.buttons["remote.passport"]; reveal(passport); passport.tap()
        let park = app.buttons["remote.park.147"]; reveal(park); shot("04-park-passport"); park.tap()
        XCTAssertTrue(app.staticTexts["Yankee Stadium"].waitForExistence(timeout: 5)); shot("05-yankee-detail")
        app.buttons["remote.detail.close"].tap()
        let sources = app.buttons["remote.sources"]; reveal(sources); sources.tap()
        XCTAssertTrue(app.navigationBars["Sources & methodology"].waitForExistence(timeout: 5)); shot("06-methodology")
        app.buttons["remote.sources.close"].tap()
        let replay = app.buttons["remote.replay"]; reveal(replay); replay.tap()
        XCTAssertFalse(app.staticTexts["remote.answer"].exists)
        XCTAssertTrue(app.buttons["remote.choice.ball-b"].isEnabled)
    }

    @MainActor func testRemoteStorySameBinaryDiscoveryOfflineAndRollback() async throws {
        try await fixture("reset"); launch()
        try await fixture("next"); app.buttons["stories.refresh"].tap()
        let second = app.buttons["stories.remote.fixture-second-story"]
        XCTAssertTrue(second.waitForExistence(timeout: 10)); second.tap()
        let choice = app.buttons["remote.choice.ball-a"]; XCTAssertTrue(choice.waitForExistence(timeout: 10)); reveal(choice); choice.tap()
        XCTAssertTrue(app.staticTexts["The same renderer, a new story."].waitForExistence(timeout: 5)); shot("07-second-story-same-binary")
        app.terminate(); try await fixture("offline"); launch()
        XCTAssertTrue(second.waitForExistence(timeout: 10)); second.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); reveal(choice); choice.tap()
        XCTAssertTrue(app.staticTexts["The same renderer, a new story."].waitForExistence(timeout: 5)); shot("08-offline-relaunch")
        app.terminate(); try await fixture("rollback"); launch()
        app.buttons["stories.refresh"].tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 10)); shot("09-catalog-rollback")
    }

    @MainActor func testRemoteStoryColdOfflineLargeTextAndReducedMotion() async throws {
        try await fixture("offline"); launch(size: "UICTContentSizeCategoryAccessibilityXXXL", reduced: true)
        openFirst(); shot("10-largest-text-cold-offline")
        let skip = app.buttons["remote.reveal"]; reveal(skip); skip.tap()
        XCTAssertTrue(app.staticTexts["remote.answer"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["remote.answer"]); shot("11-largest-text-reveal")
        let passport = app.buttons["remote.passport"]; reveal(passport); passport.tap()
        let park = app.buttons["remote.park.147"]; reveal(park); park.tap()
        XCTAssertTrue(app.staticTexts["Yankee Stadium"].waitForExistence(timeout: 5)); shot("12-largest-text-detail")
    }
    private func openChart() {
        let card = app.buttons["stories.remote.whole-season-by-june"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); reveal(card); card.tap()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["trajectory.chart"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["remote.reveal"].exists)
        XCTAssertFalse(app.buttons["remote.choice.ball-a"].exists)
    }
    private func waitForChartComplete() {
        let complete = NSPredicate(format: "label == %@", "Chart complete")
        expectation(for: complete, evaluatedWith: app.staticTexts["trajectory.status"])
        waitForExpectations(timeout: 12)
    }
    @MainActor func testTrajectoryAutoplayRemoteReplayForegroundAndOffline() async throws {
        try await fixture("reset")
        app.launchEnvironment["HUB_STORY_NO_SEED"] = "1"
        launch(); openChart(); shot("chart-01-autoplay")
        waitForChartComplete()
        let chart = app.otherElements["trajectory.chart"]
        XCTAssertGreaterThan(chart.frame.width, 100)
        XCTAssertGreaterThanOrEqual(chart.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX)
        reveal(chart); shot("chart-02-finished")
        let replay = app.buttons["trajectory.replay"]; reveal(replay); replay.tap()
        XCTAssertTrue(app.buttons["trajectory.pause"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home); app.activate()
        waitForChartComplete(); shot("chart-03-returned-to-foreground")
        app.terminate(); try await fixture("offline"); launch(); openChart()
        XCTAssertTrue(app.staticTexts["remote.cache-note"].waitForExistence(timeout: 5))
        waitForChartComplete(); reveal(app.otherElements["trajectory.chart"]); shot("chart-04-downloaded-offline")
    }
    @MainActor func testTrajectoryColdOfflineLargeTextReducedMotionAndSources() async throws {
        try await fixture("offline"); launch(size: "UICTContentSizeCategoryAccessibilityXXXL", reduced: true)
        openChart(); waitForChartComplete(); reveal(app.otherElements["trajectory.chart"])
        shot("chart-05-largest-text-reduced-motion")
        let sources = app.buttons["trajectory.sources"]; reveal(sources); sources.tap()
        XCTAssertTrue(app.navigationBars["Sources & methodology"].waitForExistence(timeout: 5)); shot("chart-06-sources")
        app.buttons["trajectory.sources.close"].tap()
        let data = app.buttons["trajectory.data"]; reveal(data); data.tap()
        XCTAssertTrue(app.navigationBars["Explore the data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2024"].exists); shot("chart-07-accessible-values")
    }
    @MainActor func testTrajectoryFinishedPreview() async throws {
        try await fixture("reset"); launch(reduced: true); openChart(); waitForChartComplete()
        shot("chart-08-phone-or-ipad-finished")
    }
    @MainActor func testBuild118ChartShowsUpdateFallback() async throws {
        try await fixture("reset"); launch()
        let card = app.buttons["stories.remote.whole-season-by-june"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); reveal(card); card.tap()
        XCTAssertTrue(app.staticTexts["A newer story experience"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Update Hub Ball")).firstMatch.exists)
        XCTAssertFalse(app.otherElements["trajectory.chart"].exists)
        shot("chart-09-build118-update-fallback")
    }

    @MainActor func testTrajectoryGenericLineAndBarRenderers() async throws {
        app.launchEnvironment["HUB_STORY_NO_SEED"] = "1"
        for kind in ["line", "bar"] {
            try await fixture("chart-" + kind); launch(reduced: true)
            let card = app.buttons["stories.remote.fixture-chart-" + kind]
            XCTAssertTrue(card.waitForExistence(timeout: 10)); reveal(card); card.tap()
            XCTAssertTrue(app.otherElements["trajectory.chart"].waitForExistence(timeout: 10))
            waitForChartComplete(); reveal(app.otherElements["trajectory.chart"]); shot("chart-generic-" + kind)
            app.terminate()
        }
    }

}
