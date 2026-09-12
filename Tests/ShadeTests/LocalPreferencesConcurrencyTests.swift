import XCTest
@testable import Shade

@MainActor
final class LocalPreferencesConcurrencyTests: XCTestCase {
    func testDirectLocalPreferencesStoreRejectsStaleSnapshotAndAcceptsFreshRetry() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let local = PreferencesStore(userDefaults: fixture.defaults)
        let checked: any PreferencesStoring = local
        let previous = local.load()
        var candidate = previous
        candidate.cursorBlink.toggle()
        let zoomedFontSize = Preferences.zoomedFontSize(from: previous.fontSize, delta: 1)
        local.saveFontSize(zoomedFontSize)

        do {
            try await checked.save(candidate, replacing: previous)
            XCTFail("The directly injected local store must also reject stale snapshots")
        } catch ConfigurationError.changedExternally {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(local.load().fontSize, zoomedFontSize)
        XCTAssertEqual(local.load().cursorBlink, previous.cursorBlink)
        let fresh = local.load()
        var retry = fresh
        retry.cursorBlink = candidate.cursorBlink
        try await checked.save(retry, replacing: fresh)

        XCTAssertEqual(local.load(), retry)
        XCTAssertEqual(local.load().fontSize, zoomedFontSize)
    }

    func testStaleLocalSnapshotCannotOverwriteZoomAndFreshRetrySucceeds() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let previous = configuration.load()
        var candidate = previous
        candidate.visualBell.toggle()
        let zoomedFontSize = Preferences.zoomedFontSize(from: previous.fontSize, delta: 1)
        try await configuration.saveFontSize(zoomedFontSize)

        do {
            try await configuration.save(candidate, replacing: previous)
            XCTFail("A stale local snapshot must not overwrite the completed zoom")
        } catch ConfigurationError.changedExternally {
            // The local backend must enforce the same snapshot contract as a
            // custom configuration folder.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(configuration.load().fontSize, zoomedFontSize)
        XCTAssertEqual(configuration.load().visualBell, previous.visualBell)
        XCTAssertNotNil(configuration.problem)
        let fresh = await configuration.reload()
        var retry = fresh
        retry.visualBell = candidate.visualBell
        try await configuration.save(retry, replacing: fresh)

        XCTAssertEqual(configuration.load(), retry)
        XCTAssertEqual(configuration.load().fontSize, zoomedFontSize)
        XCTAssertNil(configuration.problem)
    }

    func testConcurrentKeyboardZoomAndSettingsEditPreserveZoomAndAllowRetry() async throws {
        for _ in 0..<10 {
            let fixture = try ConfigurationFixture()
            defer { fixture.cleanup() }
            let configuration = fixture.store()
            let model = SettingsModel(configuration: configuration, openAtLogin: false)
            let original = configuration.load()
            let desiredVisualBell = !original.visualBell
            let zoomedFontSize = Preferences.zoomedFontSize(from: original.fontSize, delta: 1)

            // Match the keyboard zoom's reload → calculate → save → notify
            // sequence. The separate main-actor task represents a settings
            // action handled while the asynchronous zoom save is suspended.
            let zoom = Task { @MainActor in
                let current = await configuration.reload().fontSize
                let target = Preferences.zoomedFontSize(from: current, delta: 1)
                let edit = Task { @MainActor in
                    model.preferences.visualBell = desiredVisualBell
                }
                try await configuration.saveFontSize(target)
                NotificationCenter.default.post(name: .shadePreferencesChanged, object: nil)
                await edit.value
            }
            try await zoom.value
            await model.waitForPendingSave()

            XCTAssertFalse(model.isSaving)
            XCTAssertEqual(configuration.load().fontSize, zoomedFontSize)
            XCTAssertEqual(model.preferences, configuration.load())
            if let error = model.persistenceError {
                // If the settings action captured the pre-zoom snapshot, its
                // rejected edit is visible and can be retried from fresh data.
                XCTAssertEqual(error, ConfigurationError.changedExternally.localizedDescription)
                XCTAssertEqual(configuration.load().visualBell, original.visualBell)
                model.preferences.visualBell = desiredVisualBell
                await model.waitForPendingSave()
            }
            // Either scheduling order is safe: the first edit was accepted on
            // a fresh snapshot, or the explicit retry has now succeeded.
            XCTAssertEqual(configuration.load().fontSize, zoomedFontSize)
            XCTAssertEqual(configuration.load().visualBell, desiredVisualBell)
            XCTAssertEqual(model.preferences, configuration.load())
            XCTAssertNil(model.persistenceError)
        }
    }

    func testRapidLocalSettingsEditsDoNotConflictWithTheirOwnPreviousSave() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let model = SettingsModel(configuration: configuration, openAtLogin: false)

        model.preferences.fontSize = 18
        await Task.yield()
        model.preferences.fontSize = 19
        model.preferences.cursorBlink = true
        model.preferences.visualBell = true
        await model.waitForPendingSave()

        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.persistenceError)
        XCTAssertNil(configuration.problem)
        XCTAssertEqual(configuration.load().fontSize, 19)
        XCTAssertTrue(configuration.load().cursorBlink)
        XCTAssertTrue(configuration.load().visualBell)
        XCTAssertEqual(model.preferences, configuration.load())
    }
}
