import AppKit
import SwiftUI

struct ConfigurationSettingsView: View {
    @ObservedObject var configuration: ConfigurationStore
    @State private var confirmation: FolderConfirmation?
    @State private var operationError: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section("Configuration Location") {
                Label(configuration.directory == nil ? "Local Storage" : "Custom Folder",
                      systemImage: configuration.directory == nil ? "internaldrive" : "folder")
                    .font(.headline)
                Text((configuration.directory ?? configuration.localConnectionsURL.deletingLastPathComponent()).path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if configuration.directory == nil {
                    Text("Preferences use macOS defaults. Saved connections are stored in the folder above. Choosing another folder copies both into settings.json and connections.json.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Settings and SSH connections are read and saved in this folder. The previous configuration is kept at its original location.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose Folder…", action: chooseFolder)
                    Button("Show in Finder") {
                        let folder = configuration.directory
                            ?? configuration.localConnectionsURL.deletingLastPathComponent()
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                    }
                }
                HStack {
                    Button("Reload Files") {
                        perform { await configuration.reloadFromDisk() }
                    }
                    Button("Use Local Storage…") {
                        confirmation = FolderConfirmation(folder: nil, copyCurrent: false)
                    }
                    .disabled(configuration.directory == nil)
                }
            }
            .disabled(isWorking)

            if isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Updating configuration…").foregroundStyle(.secondary)
                }
            }

            if let error = operationError ?? configuration.problem {
                Section("Configuration Unavailable") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Files have not been replaced with defaults. Check the folder and reload, or choose another configuration.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Using a Shared Folder") {
                Text("You can choose a folder in iCloud Drive or another file-sync service. Changes are reloaded when opening Shade, Settings or the connection picker. Use Reload Files to refresh them now.")
                Text("Avoid editing on multiple Macs at the same time: Shade does not merge cloud conflicts. If a file changes before a save, reload and try again.")
                Text("Keep both files downloaded locally. If iCloud removes a local copy, download it in Finder before reloading.")
                Text("Connection files contain server addresses, usernames and identity-file paths, but never private keys or passwords. Keys and SSH aliases must be configured on each Mac. The global hotkey, Open at Login and macOS permissions stay local.")
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .alert(item: $confirmation) { request in
            Alert(
                title: Text(request.title),
                message: Text(request.message),
                primaryButton: .default(Text(request.action)) { activate(request) },
                secondaryButton: .cancel()
            )
        }
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "Choose Configuration Folder"
        picker.prompt = "Choose"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.allowsMultipleSelection = false
        picker.directoryURL = configuration.directory
        guard let window = NSApp.keyWindow else { return }
        picker.beginSheetModal(for: window) { result in
            guard result == .OK, let folder = picker.url else { return }
            perform {
                let contents = try await configuration.inspectFolder(folder)
                confirmation = FolderConfirmation(folder: folder, copyCurrent: contents == .empty)
            }
        }
    }

    private func activate(_ request: FolderConfirmation) {
        perform {
            if let folder = request.folder {
                try await configuration.useFolder(folder, copyCurrent: request.copyCurrent)
            } else {
                try await configuration.useLocalStorage()
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        operationError = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { try await operation() }
            catch { operationError = error.localizedDescription }
        }
    }
}

private struct FolderConfirmation: Identifiable {
    let id = UUID()
    let folder: URL?
    let copyCurrent: Bool

    var title: String {
        folder == nil ? "Use the saved local configuration?"
            : copyCurrent ? "Copy configuration to this folder?" : "Use this folder's configuration?"
    }

    var action: String {
        folder == nil ? "Use Local Storage" : copyCurrent ? "Copy and Use" : "Use Existing"
    }

    var message: String {
        guard let folder else {
            return "Restore the settings and connections saved locally before you changed folders. Changes made in the custom folder will not be copied back. The custom files remain untouched."
        }
        return "\(folder.path)\n\n" + (copyCurrent
            ? "Copy your current settings and SSH connections here, then use this folder. Original data stays at its current location."
            : "Load settings.json and connections.json from this folder. Your current configuration stays at its current location. Existing terminal sessions will not be closed.")
    }
}
