import Foundation

/// Failures of configuration documents and storage operations.
public enum ConfigurationError: LocalizedError {
    case invalidFile(String)
    case unsupportedSettingsVersion(Int)
    case invalidPreferences
    case incompleteFolder
    case notDirectory
    case destinationNotEmpty
    case useLocalStorage
    case changedExternally
    case downloadRequired(String)
    case fileTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let name):
            return "\(name) must be a regular file no larger than 5 MB, not a symbolic link."
        case .unsupportedSettingsVersion(let version):
            return "Settings file version \(version) is not supported."
        case .invalidPreferences:
            return "The settings file contains invalid or out-of-range values."
        case .incompleteFolder:
            return "The folder must contain both settings.json and connections.json, or neither. Wait for both files to download, or choose an empty folder."
        case .notDirectory:
            return "Choose a directory for the configuration files."
        case .destinationNotEmpty:
            return "Configuration files already exist in this folder. They have not been overwritten."
        case .useLocalStorage:
            return "This is Shade's local storage folder. Use Local Storage instead."
        case .changedExternally:
            return "The configuration changed outside Shade. Reload it before trying this change again."
        case .downloadRequired(let name):
            return "\(name) is not downloaded from iCloud Drive. Download it in Finder (or choose Keep Downloaded), then reload."
        case .fileTooLarge(let name):
            return "\(name) exceeds the 5 MB limit. The existing configuration has not been replaced."
        }
    }
}
