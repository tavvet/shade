import Foundation
import XCTest
@testable import Shade

@MainActor
final class ConfigurationStoreTests: XCTestCase {
    func testLocalModeDoesNotMigratePreferencesOrCreateFiles() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()

        XCTAssertNil(configuration.directory)
        XCTAssertEqual(configuration.load().fontSize, 17)
        let loadedProfiles = try await configuration.loadProfiles()
        XCTAssertEqual(loadedProfiles, fixture.profiles)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            fixture.localConnections.deletingLastPathComponent().appendingPathComponent("settings.json").path))
        XCTAssertNil(fixture.defaults.string(forKey: ConfigurationStore.directoryKey))
    }

    func testCopyCreatesPrivatePortableFilesAndPreservesOriginals() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let original = try Data(contentsOf: fixture.localConnections)
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")

        let contents = try await configuration.inspectFolder(folder)
        XCTAssertEqual(contents, .empty)
        try await configuration.useFolder(folder, copyCurrent: true)

        let files = ConfigurationFiles(directory: folder)
        let copied = try files.load()
        XCTAssertEqual(copied.preferences, configuration.load())
        XCTAssertEqual(copied.profiles, fixture.profiles)
        XCTAssertEqual(try Data(contentsOf: fixture.localConnections), original)
        XCTAssertEqual(fixture.defaults.double(forKey: PreferencesStore.Key.fontSize), 17)
        XCTAssertEqual(fixture.defaults.string(forKey: ConfigurationStore.directoryKey), folder.path)
        for url in [files.settingsURL, files.connectionsURL] {
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
        }
        let settingsJSON = try String(contentsOf: files.settingsURL, encoding: .utf8)
        XCTAssertFalse(settingsJSON.contains(ConfigurationStore.directoryKey))
        XCTAssertFalse(settingsJSON.contains("openAtLogin"))
        XCTAssertFalse(settingsJSON.contains("toggleShade"))
        XCTAssertEqual(fixture.store().directory, folder)
        XCTAssertEqual(fixture.store().load(), copied.preferences)
    }

    func testFileBackedChangesDoNotAlterPreservedLocalConfiguration() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        var preferences = configuration.load()
        let oldPreferences = preferences
        preferences.fontSize = 22
        try await configuration.save(preferences, replacing: oldPreferences)
        let profiles = [SSHProfile(name: "Other", host: "other")]
        try await configuration.saveProfiles(profiles, replacing: fixture.profiles)

        XCTAssertEqual(try ConfigurationFiles(directory: folder).load().preferences.fontSize, 22)
        XCTAssertEqual(try ConfigurationFiles(directory: folder).load().profiles, profiles)
        XCTAssertEqual(fixture.defaults.double(forKey: PreferencesStore.Key.fontSize), 17)
        let preservedProfiles = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(preservedProfiles, fixture.profiles)

        try await configuration.useLocalStorage()
        XCTAssertNil(configuration.directory)
        XCTAssertNil(fixture.defaults.string(forKey: ConfigurationStore.directoryKey))
        XCTAssertEqual(configuration.load().fontSize, 17)
        let loadedProfiles = try await configuration.loadProfiles()
        XCTAssertEqual(loadedProfiles, fixture.profiles)
        XCTAssertEqual(try ConfigurationFiles(directory: folder).load().preferences.fontSize, 22)
        XCTAssertEqual(try ConfigurationFiles(directory: folder).load().profiles, profiles)
    }

    func testUseExistingNeverReplacesTargetAndCopiesAreRejected() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("existing")
        let files = ConfigurationFiles(directory: folder)
        var preferences = Preferences.defaults
        preferences.fontSize = 23
        try files.create(.init(preferences: preferences, profiles: []))
        let before = try Data(contentsOf: files.settingsURL)

        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: true) }
        XCTAssertNil(configuration.directory)
        try await configuration.useFolder(folder, copyCurrent: false)

        XCTAssertEqual(configuration.load().fontSize, 23)
        let loadedProfiles = try await configuration.loadProfiles()
        XCTAssertEqual(loadedProfiles, [])
        XCTAssertEqual(try Data(contentsOf: files.settingsURL), before)
        XCTAssertEqual(fixture.defaults.double(forKey: PreferencesStore.Key.fontSize), 17)
    }

    func testSwitchReloadsOpenSettingsAndNotifiesOnlyTheSelectedStore() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let model = SettingsModel(configuration: configuration, openAtLogin: false)
        let spy = ConfigurationChangeSpy()
        NotificationCenter.default.addObserver(spy, selector: #selector(ConfigurationChangeSpy.changed),
                                               name: ConfigurationStore.didChange, object: configuration)
        defer { NotificationCenter.default.removeObserver(spy) }
        let folder = try fixture.folder("existing")
        var preferences = Preferences.defaults
        preferences.fontSize = 23
        try ConfigurationFiles(directory: folder).create(.init(preferences: preferences, profiles: []))

        try await configuration.useFolder(folder, copyCurrent: false)

        XCTAssertEqual(model.preferences.fontSize, 23)
        XCTAssertEqual(spy.count, 1)
        try await configuration.useLocalStorage()
        XCTAssertEqual(model.preferences.fontSize, 17)
        XCTAssertEqual(spy.count, 2)
    }

    func testIncompleteOrMalformedFolderIsNotActivatedOrOverwritten() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("incomplete")
        let files = ConfigurationFiles(directory: folder)
        try Data("invalid json".utf8).write(to: files.settingsURL)
        let original = try Data(contentsOf: files.settingsURL)

        await assertThrowsAsync { try await configuration.inspectFolder(folder) }
        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: true) }
        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: false) }
        XCTAssertNil(configuration.directory)
        XCTAssertEqual(try Data(contentsOf: files.settingsURL), original)

        try await SSHProfileStore(fileURL: files.connectionsURL).save([])
        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: false) }
        XCTAssertNil(fixture.defaults.string(forKey: ConfigurationStore.directoryKey))
    }

    func testMissingActiveFileKeepsLastSettingsAndBlocksEveryPortableWrite() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let files = ConfigurationFiles(directory: folder)
        let settings = try Data(contentsOf: files.settingsURL)
        try FileManager.default.removeItem(at: files.settingsURL)
        _ = await configuration.reload()

        XCTAssertEqual(configuration.load().fontSize, 17)
        XCTAssertNotNil(configuration.problem)
        await assertThrowsAsync { try await configuration.loadProfiles() }
        await assertThrowsAsync { try await configuration.saveFontSize(20) }
        await assertThrowsAsync { try await configuration.saveProfiles([], replacing: fixture.profiles) }
        XCTAssertEqual(configuration.directory, folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.settingsURL.path))
        let preservedProfiles = try await SSHProfileStore(fileURL: files.connectionsURL).load()
        XCTAssertEqual(preservedProfiles, fixture.profiles)

        try settings.write(to: files.settingsURL)
        await configuration.reloadFromDisk()
        XCTAssertNil(configuration.problem)
        try await configuration.saveFontSize(20)
        XCTAssertEqual(configuration.load().fontSize, 20)
    }

    func testUnavailableFolderIsNotRecreatedOnRestartOrSave() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let folder = try fixture.folder("portable")
        try await fixture.store().useFolder(folder, copyCurrent: true)
        try FileManager.default.moveItem(at: folder, to: fixture.root.appendingPathComponent("offline"))

        let restarted = fixture.store()
        _ = await restarted.reload()
        XCTAssertEqual(restarted.directory, folder)
        XCTAssertNotNil(restarted.problem)
        await assertThrowsAsync { try await restarted.saveFontSize(20) }
        await assertThrowsAsync { try await restarted.loadProfiles() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(fixture.defaults.double(forKey: PreferencesStore.Key.fontSize), 17)
    }

    func testStaleSettingsEditIsRejectedAndModelReloadsExternalValues() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let model = SettingsModel(configuration: configuration, openAtLogin: false)
        var external = model.preferences
        external.fontSize = 24
        let files = ConfigurationFiles(directory: folder)
        let data = try SettingsFileDocument.encode(external)
        try data.write(to: files.settingsURL, options: .atomic)

        model.preferences.visualBell = true
        await model.waitForPendingSave()

        XCTAssertNotNil(model.persistenceError)
        XCTAssertEqual(model.preferences.fontSize, 24)
        XCTAssertFalse(model.preferences.visualBell)
        XCTAssertEqual(try Data(contentsOf: files.settingsURL), data)

        model.preferences.visualBell = true
        await model.waitForPendingSave()
        XCTAssertNil(model.persistenceError)
        XCTAssertTrue(try files.load().preferences.visualBell)
        XCTAssertEqual(try files.load().preferences.fontSize, 24)
    }

    func testFontZoomStartsFromLatestFileInsteadOfOverwritingOtherChanges() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        var external = configuration.load()
        external.backgroundBlur = false
        let files = ConfigurationFiles(directory: folder)
        try SettingsFileDocument.encode(external).write(to: files.settingsURL)

        try await configuration.saveFontSize(21)

        XCTAssertFalse(try files.load().preferences.backgroundBlur)
        XCTAssertEqual(try files.load().preferences.fontSize, 21)
    }

    func testStaleConnectionEditCannotOverwriteNewlyArrivedProfiles() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        try await configuration.useFolder(folder, copyCurrent: true)
        let controller = SSHConnectionsController(
            store: ConfigurationSSHProfileStore(configuration: configuration), connect: { _ in }
        )
        await controller.reload()
        let external = fixture.profiles + [SSHProfile(name: "Arrived", host: "new")]
        let files = ConfigurationFiles(directory: folder)
        try await SSHProfileStore(fileURL: files.connectionsURL).save(external)
        // Reading settings updates the shared cache, but must not make the
        // controller's older profile snapshot a valid overwrite base.
        _ = await configuration.reload()

        await assertThrowsAsync { try await controller.remove(id: fixture.profiles[0].id) }
        XCTAssertEqual(try files.load().profiles, external)
        XCTAssertNotNil(controller.problem)
        await controller.reload()
        try await controller.remove(id: fixture.profiles[0].id)
        XCTAssertEqual(try files.load().profiles, Array(external.dropFirst()))
    }

    func testBrokenCurrentFolderCanBeReplacedByAnotherValidFolder() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let broken = try fixture.folder("broken")
        try await configuration.useFolder(broken, copyCurrent: true)
        try Data("broken".utf8).write(to: ConfigurationFiles(directory: broken).settingsURL)
        let replacement = try fixture.folder("replacement")
        try ConfigurationFiles(directory: replacement).create(.init(preferences: .defaults, profiles: []))

        try await configuration.useFolder(replacement, copyCurrent: false)

        XCTAssertEqual(configuration.directory, replacement)
        XCTAssertEqual(configuration.load(), .defaults)
        XCTAssertNil(configuration.problem)
    }

    func testPortableSnapshotCannotOverwritePreservedLocalLibraryAfterSwitch() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("portable")
        let portable = [SSHProfile(name: "Portable", host: "portable")]
        try ConfigurationFiles(directory: folder).create(.init(preferences: .defaults, profiles: portable))
        try await configuration.useFolder(folder, copyCurrent: false)
        let controller = SSHConnectionsController(store: ConfigurationSSHProfileStore(configuration: configuration)) { _ in }
        await controller.reload()
        try await configuration.useLocalStorage()

        // Even if a caller misses the location notification and retains the old
        // snapshot, the storage boundary must reject that overwrite base.
        await assertThrowsAsync { try await controller.add(SSHProfile(name: "Added", host: "added")) }

        let local = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(local, fixture.profiles)
        XCTAssertEqual(try ConfigurationFiles(directory: folder).load().profiles, portable)
        await controller.reload()
        let added = SSHProfile(name: "Added", host: "added")
        try await controller.add(added)
        let updated = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(updated, fixture.profiles + [added])
    }

    func testLocalSaveRejectsStaleSnapshotButCanCreateAnInitiallyMissingLibrary() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let external = fixture.profiles + [SSHProfile(name: "External", host: "external")]
        try await SSHProfileStore(fileURL: fixture.localConnections).save(external)

        await assertThrowsAsync { try await configuration.saveProfiles([], replacing: fixture.profiles) }
        let preserved = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(preserved, external)

        try FileManager.default.removeItem(at: fixture.localConnections)
        try await configuration.saveProfiles(fixture.profiles, replacing: [])
        let created = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(created, fixture.profiles)
    }

    func testLocalFolderAndSymlinkedFilesAreRejectedAsPortableConfiguration() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        await assertThrowsAsync { try await configuration.inspectFolder(fixture.localConnections.deletingLastPathComponent()) }
        let folder = try fixture.folder("linked")
        let files = ConfigurationFiles(directory: folder)
        try SettingsFileDocument.encode(.defaults).write(to: files.settingsURL)
        try FileManager.default.createSymbolicLink(at: files.connectionsURL, withDestinationURL: fixture.localConnections)

        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: false) }
        XCTAssertNil(configuration.directory)
        let preservedProfiles = try await SSHProfileStore(fileURL: fixture.localConnections).load()
        XCTAssertEqual(preservedProfiles, fixture.profiles)
    }

    func testBrokenLocalConnectionFileDoesNotBlockLocalPreferences() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        try Data("broken".utf8).write(to: fixture.localConnections)
        let configuration = fixture.store()
        let previous = configuration.load()
        var updated = previous
        updated.cursorBlink = true

        try await configuration.save(updated, replacing: previous)

        XCTAssertTrue(configuration.load().cursorBlink)
        await assertThrowsAsync { try await configuration.loadProfiles() }
        await assertThrowsAsync { try await configuration.useFolder(fixture.folder("destination"), copyCurrent: true) }
        XCTAssertNil(configuration.directory)
    }

    func testReadOnlyFolderRejectsSavesAndRevertsSettingsUI() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("read-only")
        try await configuration.useFolder(folder, copyCurrent: true)
        let files = ConfigurationFiles(directory: folder)
        let settings = try Data(contentsOf: files.settingsURL)
        let connections = try Data(contentsOf: files.connectionsURL)
        let model = SettingsModel(configuration: configuration, openAtLogin: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        model.preferences.fontSize = 22
        await model.waitForPendingSave()

        XCTAssertEqual(model.preferences.fontSize, 17)
        XCTAssertNotNil(model.persistenceError)
        await assertThrowsAsync { try await configuration.saveProfiles([], replacing: fixture.profiles) }
        XCTAssertEqual(try Data(contentsOf: files.settingsURL), settings)
        XCTAssertEqual(try Data(contentsOf: files.connectionsURL), connections)
    }

    func testReadOnlyDestinationDoesNotSwitchLocationOrAlterOriginals() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let folder = try fixture.folder("read-only")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        await assertThrowsAsync { try await configuration.useFolder(folder, copyCurrent: true) }

        XCTAssertNil(configuration.directory)
        XCTAssertNil(fixture.defaults.string(forKey: ConfigurationStore.directoryKey))
        XCTAssertEqual(configuration.load().fontSize, 17)
        let loadedProfiles = try await configuration.loadProfiles()
        XCTAssertEqual(loadedProfiles, fixture.profiles)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ConfigurationFiles(directory: folder).settingsURL.path))
    }
}

@MainActor
private final class ConfigurationChangeSpy: NSObject {
    private(set) var count = 0
    @objc func changed() { count += 1 }
}

@MainActor
final class ConfigurationFixture {
    let root: URL
    let suite = "ConfigurationStoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let localConnections: URL
    let profiles = [SSHProfile(name: "First", host: "first"), SSHProfile(name: "Second", host: "second")]

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadeConfigurationTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defaults = UserDefaults(suiteName: suite)!
        localConnections = root.appendingPathComponent("local/connections.json")
        defaults.set(17, forKey: PreferencesStore.Key.fontSize)
        try SSHProfileStore(fileURL: localConnections).save(profiles)
    }

    func store() -> ConfigurationStore {
        ConfigurationStore(userDefaults: defaults, localConnectionsURL: localConnections)
    }

    func folder(_ name: String) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
