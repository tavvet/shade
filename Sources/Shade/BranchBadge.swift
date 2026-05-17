import SwiftUI

/// Small floating pill anchored to the top-right of the terminal area showing
/// the git branch of the active session. Hidden when not inside a repo.
struct BranchBadgeView: View {
    @ObservedObject var tabs: TabsObservable

    var body: some View {
        if !tabs.activeBranch.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                    Text(tabs.activeBranch)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))

                if let status = tabs.activeStatus, !status.isClean {
                    Divider()
                        .frame(height: 12)
                        .overlay(Color.white.opacity(0.18))
                    HStack(spacing: 6) {
                        if status.filesChanged > 0 {
                            countLabel(symbol: "±", value: status.filesChanged, color: .white.opacity(0.85))
                        }
                        if status.insertions > 0 {
                            countLabel(symbol: "+", value: status.insertions, color: .green.opacity(0.95))
                        }
                        if status.deletions > 0 {
                            countLabel(symbol: "−", value: status.deletions, color: .red.opacity(0.95))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .fixedSize(horizontal: true, vertical: false)
            .help("Current git branch and uncommitted changes")
            .allowsHitTesting(false)
            .padding(.top, 6)
            .padding(.trailing, 10)
        }
    }

    @ViewBuilder
    private func countLabel(symbol: String, value: Int, color: Color) -> some View {
        Text("\(symbol)\(value)")
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
    }
}
