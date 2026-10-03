import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @State private var whitelistAnchor: NSRect = .zero
    @State private var hostWindow: NSWindow?

    private var settings: SettingsStore { .shared }
    private var stats: StatsManager { .shared }
    private var whitelist: WhitelistManager { .shared }
    private var permissions: PermissionsManager { .shared }
    private var roster: AppRoster { .shared }
    private var flyout: WhitelistFlyoutController { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !permissions.isTrusted {
                permissionBanner
                    .padding(.top, 10)
            }
            statisticsCard
                .padding(.top, 12)

            rowDivider
                .padding(.vertical, 10)

            PopoverRow(
                symbol: "checklist",
                title: "Smart Whitelist",
                trailingText: "\(whitelist.count) app\(whitelist.count == 1 ? "" : "s")",
                showsChevron: true,
                chevronPointsLeft: true
            ) {
                // Hover is the primary affordance; a click pins or dismisses
                // the panel for anyone navigating without a steady pointer.
                flyout.togglePinned(anchor: whitelistAnchor, host: hostWindow)
            }
            .background {
                AnchorReader { rect, window in
                    whitelistAnchor = rect
                    hostWindow = window
                }
            }
            .onHover { inside in
                flyout.triggerHover(inside, anchor: whitelistAnchor, host: hostWindow)
            }

            PopoverRow(
                symbol: settings.isPaused ? "play.circle" : "pause.circle",
                title: settings.isPaused ? "Resume Now" : "Pause for 1 Hour",
                trailingText: pauseRemainingText
            ) {
                if settings.isPaused { settings.resume() } else { settings.pause(for: 3600) }
            }
            .disabled(!settings.isEnabled)

            rowDivider
                .padding(.vertical, 10)

            PopoverRow(symbol: "gearshape", title: "Preferences…", trailingText: "⌘,") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            PopoverRow(symbol: "power", title: "Quit DotQuit", trailingText: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(DQ.Metric.popoverInset)
        .frame(width: DQ.Metric.popoverWidth)
        .onDisappear { WhitelistFlyoutController.shared.close() }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var settings = SettingsStore.shared
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    PulsingDot(color: statusColor, isPulsing: settings.isActive, size: 9)
                    Text(settings.statusText)
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(statusSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Enable DotQuit", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var statusColor: Color {
        if !settings.isEnabled { return .secondary }
        return settings.isPaused ? DQ.paused : DQ.online
    }

    private var statusSubtitle: String {
        if !permissions.isTrusted { return "Accessibility access needed" }
        if !settings.isEnabled { return "Close buttons are ignored" }
        if settings.isPaused, let until = settings.pausedUntil {
            return "Resumes at \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "Watching close buttons"
    }

    private var pauseRemainingText: String? {
        guard settings.isPaused, let until = settings.pausedUntil else { return nil }
        let minutes = max(1, Int(until.timeIntervalSinceNow / 60))
        return "\(minutes) min left"
    }

    private var permissionBanner: some View {
        Button {
            permissions.requestAccess()
            permissions.openSystemSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DQ.paused)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Grant Accessibility access")
                        .font(.system(size: 12, weight: .medium))
                    Text("DotQuit can't watch windows without it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(DQ.paused.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Statistics

    private var statisticsCard: some View {
        HStack(spacing: 0) {
            PopoverStat(label: "Apps Closed Today", value: "\(stats.closedToday)")
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 36)
            PopoverStat(label: "RAM Saved", value: "~" + stats.ramSavedTodayText)
        }
        .padding(.vertical, 10)
        .background(DQ.popoverInsetCard, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
    }
}

// MARK: - Pieces

private struct PopoverStat: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

private struct PopoverRowLabel: View {
    var symbol: String
    var title: String
    var trailingText: String?
    var showsChevron: Bool
    /// Submenu indicator pointing at the left-anchored flyout.
    var chevronPointsLeft = false
    var indented = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: chevronPointsLeft ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, indented ? 8 : 0)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

/// Hover highlight that matches a menu row.
private struct PopoverRowButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .onHover { isHovering = $0 }
    }
}

private struct PopoverRow: View {
    var symbol: String
    var title: String
    var trailingText: String?
    var showsChevron = false
    var chevronPointsLeft = false
    var indented = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PopoverRowLabel(
                symbol: symbol,
                title: title,
                trailingText: trailingText,
                showsChevron: showsChevron,
                chevronPointsLeft: chevronPointsLeft,
                indented: indented
            )
        }
        .buttonStyle(PopoverRowButtonStyle())
    }
}
