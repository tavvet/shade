import AppKit
import Carbon
import Combine
import Foundation

struct InputSourceDescriptor: Equatable, Sendable {
    let identifier: String
    let localizedName: String
    let primaryLanguage: String?

    /// Compact language marker for the tab bar. Text Input Sources reports its
    /// intended language as BCP 47; keep the base language subtag so variants
    /// such as `en-US` and `zh-Hans` remain compact (`EN`, `ZH`). Sources with
    /// no language, such as Unicode Hex Input, fall back to their system name.
    var badgeLabel: String {
        if let languageLabel = Self.languageLabel(from: primaryLanguage) {
            return languageLabel
        }
        let name = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "?" : name
    }

    var diagnosticsDescription: String {
        let trimmedName = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "(unnamed)" : trimmedName
        return "\(badgeLabel) — \(name) [\(identifier)]"
    }

    private static func languageLabel(from language: String?) -> String? {
        guard let language else { return nil }
        let base = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1) { $0 == "-" || $0 == "_" }
            .first
            .map(String.init) ?? ""
        guard (2...3).contains(base.count),
              base.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
            return nil
        }
        return base.uppercased()
    }
}

protocol InputSourceProviding {
    func currentInputSource() -> InputSourceDescriptor?
}

struct SystemInputSourceProvider: InputSourceProviding {
    func currentInputSource() -> InputSourceDescriptor? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let identifier: String = property(kTISPropertyInputSourceID, from: source) else {
            return nil
        }
        let localizedName: String = property(kTISPropertyLocalizedName, from: source) ?? identifier
        let languages: [String]? = property(kTISPropertyInputSourceLanguages, from: source)
        return InputSourceDescriptor(
            identifier: identifier,
            localizedName: localizedName,
            primaryLanguage: languages?.first
        )
    }

    private func property<Value>(
        _ key: CFString,
        from source: TISInputSource
    ) -> Value? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>
            .fromOpaque(pointer)
            .takeUnretainedValue() as? Value
    }
}

/// Event-driven observable state for the optional input-source indicator.
/// Disabled instances do not observe the text system; enabling or re-applying
/// the preference performs a synchronous refresh so a newly shown panel never
/// displays stale state.
@MainActor
final class InputSourceMonitor: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var current: InputSourceDescriptor?

    private let provider: any InputSourceProviding
    private let notificationCenter: NotificationCenter
    private var isObserving = false

    var diagnosticsDescription: String {
        guard isEnabled else { return "disabled" }
        return current?.diagnosticsDescription ?? "unavailable"
    }

    init(
        provider: any InputSourceProviding = SystemInputSourceProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.provider = provider
        self.notificationCenter = notificationCenter
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled == isEnabled {
            if enabled { refresh() }
            return
        }

        isEnabled = enabled
        if enabled {
            startObserving()
            refresh()
        } else {
            stopObserving()
            current = nil
        }
    }

    func refresh() {
        guard isEnabled else { return }
        current = provider.currentInputSource()
    }

    private func startObserving() {
        guard !isObserving else { return }
        notificationCenter.addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        isObserving = true
    }

    private func stopObserving() {
        guard isObserving else { return }
        notificationCenter.removeObserver(
            self,
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        isObserving = false
    }

    @objc private func inputSourceDidChange(_ notification: Notification) {
        refresh()
    }
}
