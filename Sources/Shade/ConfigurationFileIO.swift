import Foundation

enum ConfigurationFileIO {
    static let maximumFileSize = 5 * 1_024 * 1_024

    /// Coordinate with file providers and readers before comparing and replacing
    /// a file. An offline Mac can still create a cloud conflict later; this guards
    /// against overwriting a change already visible on this Mac.
    static func update<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        try requireLocalDownload(at: url)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                      error: &coordinationError) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let result { return try result.get() }
        throw coordinationError ?? CocoaError(.fileWriteUnknown)
    }

    static func read(at url: URL) throws -> Data {
        try requireLocalDownload(at: url)
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [],
                                      error: &coordinationError) { coordinatedURL in
            result = Result { try readUncoordinated(at: coordinatedURL) }
        }
        if let result { return try result.get() }
        throw coordinationError ?? CocoaError(.fileReadUnknown)
    }

    static func readUncoordinated(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= maximumFileSize else {
            throw ConfigurationError.invalidFile(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        try validateSize(data, at: url)
        return data
    }

    private static func requireLocalDownload(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ])
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus == .notDownloaded {
            // Coordinating an evicted iCloud document may wait for a network
            // download. Never initiate that wait from a settings or F12 action.
            throw ConfigurationError.downloadRequired(url.lastPathComponent)
        }
    }

    /// The sibling is private before it contains data; replacing keeps those
    /// permissions. No operation that can fail follows the final rename.
    static func replace(_ data: Data, at url: URL, allowOverwrite: Bool = true) throws {
        try validateSize(data, at: url)
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".shade-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data,
                                 attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        if allowOverwrite, manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary,
                                          options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }

    static func validateSize(_ data: Data, at url: URL) throws {
        guard data.count <= maximumFileSize else {
            throw ConfigurationError.fileTooLarge(url.lastPathComponent)
        }
    }
}
