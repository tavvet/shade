import Combine
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case connections
    case appearance
    case terminal
    case notifications
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .general:       return "General"
        case .connections:   return "Connections"
        case .appearance:    return "Appearance"
        case .terminal:      return "Terminal"
        case .notifications: return "Notifications"
        case .shortcuts:     return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .general:       return "Window layout, startup and tab behavior"
        case .connections:   return "Saved SSH servers and quick-access order"
        case .appearance:    return "Typography, color and background"
        case .terminal:      return "Shell integration and terminal behavior"
        case .notifications: return "Command completion alerts"
        case .shortcuts:     return "Global hotkey and keyboard reference"
        }
    }

    var systemImage: String {
        switch self {
        case .general:       return "gearshape"
        case .connections:   return "network"
        case .appearance:    return "paintbrush"
        case .terminal:      return "terminal"
        case .notifications: return "bell"
        case .shortcuts:     return "keyboard"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage? = .general
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var connections: SSHConnectionsController
    @ObservedObject var navigation: SettingsNavigation

    private var selectedPage: SettingsPage {
        navigation.selection ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $navigation.selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
        } detail: {
            VStack(spacing: 0) {
                pageHeader(selectedPage)
                Divider()
                selectedPageView
                    .id(selectedPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 500)
    }

    @ViewBuilder
    private var selectedPageView: some View {
        switch selectedPage {
        case .general:
            GeneralSettingsView(model: model)
        case .connections:
            ConnectionsSettingsView(controller: connections)
        case .appearance:
            AppearanceSettingsView(model: model)
        case .terminal:
            TerminalSettingsView(model: model)
        case .notifications:
            NotificationSettingsView(model: model)
        case .shortcuts:
            ShortcutsSettingsView()
        }
    }

    private func pageHeader(_ page: SettingsPage) -> some View {
        HStack(spacing: 13) {
            Image(systemName: page.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                Text(page.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
