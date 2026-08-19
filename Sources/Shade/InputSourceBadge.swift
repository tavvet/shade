import SwiftUI

/// Compact, read-only input-source marker kept outside the scrollable tab
/// strip so it remains visible no matter how many tabs are open.
struct InputSourceBadge: View {
    @ObservedObject var inputSource: InputSourceMonitor

    private var label: String {
        inputSource.current?.badgeLabel ?? "?"
    }

    private var localizedName: String {
        guard let name = inputSource.current?.localizedName
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "Unavailable"
        }
        return name
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 18, maxWidth: 58)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.14), lineWidth: 0.5)
            }
            .help("Current input source: \(localizedName)")
            .accessibilityLabel("Current input source")
            .accessibilityValue(localizedName)
    }
}
