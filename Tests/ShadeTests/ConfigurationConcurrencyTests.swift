import Foundation
import XCTest
@testable import Shade

@MainActor
final class ConfigurationConcurrencyTests: XCTestCase {
    func testCoordinatedReloadAndSaveLeaveMainActorAndCachedSettingsAvailable() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let files = ConfigurationFiles(directory: folder)
        let acquired = expectation(description: "Writer acquired coordination")
        let release = DispatchSemaphore(value: 0)
        let writer = Task.detached {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: files.settingsURL, options: .forReplacing, error: &error) { _ in
                acquired.fulfill()
                _ = release.wait(timeout: .now() + 5)
            }
            if let error { throw error }
        }
        defer { release.signal() }
        await fulfillment(of: [acquired], timeout: 2)

        var reloadFinished = false
        var saveFinished = false
        let previous = configuration.load()
        let refresh = Task { _ = await configuration.reload(); reloadFinished = true }
        var drainFinished = false
        let drain = Task { await configuration.waitForPendingWrites(); drainFinished = true }
        // A background refresh alone must not delay a normal quit.
        await drain.value
        XCTAssertTrue(drainFinished)
        let save = Task {
            var updated = previous
            updated.fontSize = 21
            try await configuration.save(updated, replacing: previous)
            saveFinished = true
        }
        let start = Date()
        try await Task.sleep(for: .milliseconds(100))
        // If either operation blocks the main actor, this continuation cannot
        // run until the writer's five-second emergency timeout releases it.
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertFalse(reloadFinished)
        XCTAssertFalse(saveFinished)
        XCTAssertEqual(configuration.load(), previous)

        release.signal()
        try await writer.value
        await refresh.value
        try await save.value
        XCTAssertEqual(configuration.load().fontSize, 21)
    }

    func testOpenEditorCannotOverwriteExternalProfileAfterControllerReload() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let controller = SSHConnectionsController(store: ConfigurationSSHProfileStore(configuration: configuration)) { _ in }
        await controller.reload()
        let state = ConnectionsSettingsViewState()
        let original = controller.profiles[0]
        state.beginEditing(original, canEditProfiles: controller.canEditProfiles)
        let context = try XCTUnwrap(state.editor)
        var draft = original
        draft.name = "Renamed locally"
        var external = fixture.profiles
        external[0].host = "changed-on-another-mac.example"
        let files = ConfigurationFiles(directory: folder)
        try SSHProfileStore.encode(external).write(to: files.connectionsURL, options: .atomic)
        await controller.reload()

        await assertThrowsAsync { try await state.save(draft, context: context, using: controller) }

        XCTAssertEqual(try files.load().profiles, external)
        XCTAssertEqual(state.editor, context)
        XCTAssertEqual(controller.profiles, external)
        // A newly opened editor is based on the refreshed profile and can save.
        state.beginEditing(external[0], canEditProfiles: controller.canEditProfiles)
        var fresh = external[0]
        fresh.name = draft.name
        try await state.save(fresh, context: XCTUnwrap(state.editor), using: controller)
        XCTAssertEqual(try files.load().profiles[0], fresh)
    }

    func testOversizedSaveKeepsBothExistingFilesReadableAndUnchanged() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let files = ConfigurationFiles(directory: folder)
        let settings = try Data(contentsOf: files.settingsURL)
        let connections = try Data(contentsOf: files.connectionsURL)
        var oversized = fixture.profiles
        oversized[0].name = String(repeating: "x", count: ConfigurationFileIO.maximumFileSize)

        await assertThrowsAsync { try await configuration.saveProfiles(oversized, replacing: fixture.profiles) }

        XCTAssertEqual(try Data(contentsOf: files.settingsURL), settings)
        XCTAssertEqual(try Data(contentsOf: files.connectionsURL), connections)
        let loaded = try await configuration.loadProfiles()
        XCTAssertEqual(loaded, fixture.profiles)
        XCTAssertNil(configuration.problem)
    }

    func testOversizedCopyIsRejectedBeforeCreatingEitherFile() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let folder = try fixture.folder("destination")
        let files = ConfigurationFiles(directory: folder)
        let large = SSHProfile(name: String(repeating: "x", count: ConfigurationFileIO.maximumFileSize), host: "host")

        XCTAssertThrowsError(try files.create(.init(preferences: .defaults, profiles: [large])))

        XCTAssertFalse(FileManager.default.fileExists(atPath: files.settingsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.connectionsURL.path))
    }

    func testRapidSettingsEditsArePersistedInOrderWithoutSelfConflicts() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let model = SettingsModel(preferences: configuration, openAtLogin: false)
        model.preferences.fontSize = 18
        await Task.yield()
        model.preferences.fontSize = 19
        model.preferences.cursorBlink = true
        await model.waitForPendingSave()

        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.persistenceError)
        let saved = try ConfigurationFiles(directory: folder).load().preferences
        XCTAssertEqual(saved.fontSize, 19)
        XCTAssertTrue(saved.cursorBlink)
        XCTAssertEqual(model.preferences, saved)
    }

    func testStartupRefreshReplacesFallbackAndUpdatesOpenSettings() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let folder = try fixture.folder("existing")
        var external = Preferences.defaults
        external.fontSize = 23
        try ConfigurationFiles(directory: folder).create(.init(preferences: external, profiles: fixture.profiles))
        fixture.defaults.set(folder.path, forKey: ConfigurationStore.directoryKey)
        let configuration = fixture.store()
        let model = SettingsModel(preferences: configuration, openAtLogin: false)
        XCTAssertEqual(configuration.load().fontSize, 17)

        _ = await configuration.reload()

        XCTAssertEqual(configuration.load().fontSize, 23)
        XCTAssertEqual(model.preferences.fontSize, 23)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.persistenceError)
    }
}
