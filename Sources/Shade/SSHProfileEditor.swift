import AppKit
import SwiftUI
import ShadeCore

/// String-backed editor state keeps partially entered values out of the domain
/// model until Save, where the same normalization rules used by persistence run.
struct SSHProfileDraft: Equatable {
    let id: UUID
    var name: String
    var host: String
    var username: String
    var port: String
    var identityFile: String

    init(profile: SSHProfile) {
        id = profile.id
        name = profile.name
        host = profile.host
        username = profile.username ?? ""
        port = profile.port.map(String.init) ?? ""
        identityFile = profile.identityFile ?? ""
    }

    func makeProfile() throws -> SSHProfile {
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort: Int?
        if portText.isEmpty {
            parsedPort = nil
        } else if let value = Int(portText) {
            parsedPort = value
        } else {
            throw SSHProfileDraftError.invalidPort(portText)
        }

        return try SSHProfile(
            id: id,
            name: name,
            host: host,
            username: username,
            port: parsedPort,
            identityFile: identityFile
        ).normalized()
    }
}

enum SSHProfileDraftError: Error, Equatable, LocalizedError {
    case invalidPort(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let value):
            return "\"\(value)\" is not a valid port number."
        }
    }
}

struct SSHProfileEditorView: View {
    private enum Field: Hashable {
        case name
        case host
    }

    let isNew: Bool
    let onSave: (SSHProfile) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SSHProfileDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    init(
        profile: SSHProfile,
        isNew: Bool,
        onSave: @escaping (SSHProfile) async throws -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: SSHProfileDraft(profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "New SSH Connection" : "Edit SSH Connection")
                        .font(.title2.weight(.semibold))
                    Text("Shade uses the system OpenSSH client.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            Form {
                Section("Connection") {
                    editorRow("Name") {
                        TextField("Name", text: $draft.name)
                            .focused($focusedField, equals: .name)
                    }
                    editorRow("Host or SSH config alias") {
                        TextField("Host or SSH config alias", text: $draft.host)
                            .font(.system(.body, design: .monospaced))
                            .focused($focusedField, equals: .host)
                    }
                    editorRow("Username") {
                        TextField("Username", text: $draft.username)
                            .font(.system(.body, design: .monospaced))
                    }
                    editorRow("Port") {
                        TextField("Port", text: $draft.port)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 100)
                    }
                }

                Section("Authentication") {
                    editorRow("Identity file") {
                        HStack(spacing: 8) {
                            TextField(
                                "Identity file", text: $draft.identityFile, prompt: Text("Optional")
                            )
                            .font(.system(.body, design: .monospaced))
                            Button("Choose…", action: chooseIdentityFile)
                            if !draft.identityFile.isEmpty {
                                Button {
                                    draft.identityFile = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Clear identity file")
                            }
                        }
                    }

                    Text("Passwords and passphrases are never stored. ProxyJump, forwarding, "
                         + "keepalive and other advanced options remain in ~/.ssh/config.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)

            Divider()

            HStack {
                if isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Connection" : "Save Changes", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 540)
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            focusedField = isNew ? .name : .host
        }
    }

    private func editorRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 150, alignment: .leading)
            content()
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let profile = try draft.makeProfile()
                try await onSave(profile)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Identity File"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".ssh", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = url.path
        }
    }
}
