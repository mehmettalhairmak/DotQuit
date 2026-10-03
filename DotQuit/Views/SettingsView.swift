import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case behavior, whitelist, license, shortcuts, appearance, general

    var id: String { rawValue }

    /// Sidebar grouping, matching the two-section sidebar in the references.
    enum Group: String, CaseIterable, Identifiable {
        case dotQuit = "DotQuit"
        case system = "System"

        var id: String { rawValue }

        var panes: [SettingsPane] {
            switch self {
            case .dotQuit: [.behavior, .whitelist, .license]
            case .system: [.shortcuts, .appearance, .general]
            }
        }
    }

    var title: String {
        switch self {
        case .behavior: "Behavior"
        case .whitelist: "Whitelist"
        case .license: "License"
        case .shortcuts: "Shortcuts & Permissions"
        case .appearance: "Appearance"
        case .general: "General"
        }
    }

    /// Shorter label for the sidebar, which is only 231pt wide.
    var sidebarTitle: String {
        self == .shortcuts ? "Shortcuts" : title
    }

    var symbol: String {
        switch self {
        case .behavior: "slider.horizontal.3"
        case .whitelist: "square.grid.2x2"
        case .license: "key"
        case .shortcuts: "command"
        case .appearance: "circle.lefthalf.filled"
        case .general: "gearshape"
        }
    }

    /// Extra terms the sidebar search should match.
    var keywords: [String] {
        switch self {
        case .behavior: ["quit", "close", "option", "mode", "sound", "haptic"]
        case .whitelist: ["apps", "exempt", "allow", "ignore"]
        case .license: ["pro", "polar", "purchase", "key", "trial"]
        case .shortcuts: ["accessibility", "permission", "hotkey", "keyboard"]
        case .appearance: ["theme", "dark", "light", "icon", "dock"]
        case .general: ["login", "startup", "statistics", "reset", "version"]
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane = .behavior
    @State private var search = ""
    @State private var history = PaneHistory()

    private var settings: SettingsStore { .shared }

    var body: some View {
        // Composed by hand rather than with NavigationSplitView: that view
        // draws a floating sidebar-collapse button this design has no place
        // for, and the only API to remove it — .toolbar(removing: .sidebarToggle)
        // — stops the window being created at all on this OS.
        HStack(spacing: 0) {
            sidebar
                .frame(width: DQ.Metric.sidebarWidth)
                .background(VibrantBackground(material: .sidebar))

            VStack(spacing: 0) {
                titleBar
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                detail
            }
            .frame(maxWidth: .infinity)
            .background(DQ.content)
            // Drawn inside the opaque column so no desktop shows through the
            // seam between the vibrant sidebar and the content.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 1)
            }
        }
        .ignoresSafeArea(.container, edges: .all)
    }

    /// Back / forward / title, drawn inside the transparent title bar band.
    private var titleBar: some View {
        HStack(spacing: 14) {
            Button {
                if let pane = history.goBack(from: selection) { select(pane, record: false) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!history.canGoBack)
            .foregroundStyle(history.canGoBack ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .help("Back")

            Button {
                if let pane = history.goForward(from: selection) { select(pane, record: false) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!history.canGoForward)
            .foregroundStyle(history.canGoForward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .help("Forward")

            Text(selection.title)
                .font(.system(size: 16, weight: .semibold))
                .padding(.leading, 10)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, DQ.Metric.sidebarInset)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SettingsPane.Group.allCases) { group in
                        let panes = group.panes.filter(matchesSearch)
                        if !panes.isEmpty {
                            Text(group.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DQ.Metric.sidebarInset + 4)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(panes) { pane in
                                SidebarRow(pane: pane, isSelected: selection == pane) {
                                    select(pane)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DQ.Metric.sidebarInset)
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
            SidebarStatusCapsule()
                .padding(DQ.Metric.sidebarInset)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 52) // clears the traffic lights in the transparent title bar
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(DQ.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func matchesSearch(_ pane: SettingsPane) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if pane.title.localizedCaseInsensitiveContains(query) { return true }
        return pane.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func select(_ pane: SettingsPane, record: Bool = true) {
        guard pane != selection else { return }
        if record { history.push(selection) }
        selection = pane
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .behavior: BehaviorView()
        case .whitelist: WhitelistView()
        case .license: LicenseView()
        case .shortcuts: ShortcutsView()
        case .appearance: AppearanceView()
        case .general: GeneralView()
        }
    }
}

// MARK: - Sidebar pieces

private struct SidebarRow: View {
    var pane: SettingsPane
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(pane.sidebarTitle)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .frame(height: DQ.Metric.sidebarRowHeight)
            .background {
                RoundedRectangle(cornerRadius: DQ.Metric.sidebarRowRadius, style: .continuous)
                    .fill(background)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        if isHovering { return AnyShapeStyle(Color.primary.opacity(0.07)) }
        return AnyShapeStyle(Color.clear)
    }
}

/// Bottom-left capsule: live watcher state on top, license tier underneath.
private struct SidebarStatusCapsule: View {
    private var settings: SettingsStore { .shared }
    private var license: LicenseManager { .shared }

    var body: some View {
        HStack(spacing: 9) {
            PulsingDot(color: statusColor, isPulsing: settings.isActive, size: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DQ.capsuleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Product name carries the licence tier; the run state is only spelled
    /// out when it isn't the normal "watching" case, which the dot already says.
    private var headline: String {
        let name = license.isPro ? "DotQuit Pro" : "DotQuit"
        return settings.isActive ? name : "\(name) — \(settings.statusText)"
    }

    private var subtitle: String { license.status.tierLabel }

    private var statusColor: Color {
        if !settings.isEnabled { return .secondary }
        return settings.isPaused ? DQ.paused : DQ.online
    }
}

/// Back/forward stack for the toolbar chevrons.
@Observable
private final class PaneHistory {
    private var back: [SettingsPane] = []
    private var forward: [SettingsPane] = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func push(_ pane: SettingsPane) {
        back.append(pane)
        forward.removeAll()
    }

    func goBack(from current: SettingsPane) -> SettingsPane? {
        guard let pane = back.popLast() else { return nil }
        forward.append(current)
        return pane
    }

    func goForward(from current: SettingsPane) -> SettingsPane? {
        guard let pane = forward.popLast() else { return nil }
        back.append(current)
        return pane
    }
}

#Preview {
    SettingsView()
}


/// Real sidebar vibrancy — the window is transparent behind it.
private struct VibrantBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
