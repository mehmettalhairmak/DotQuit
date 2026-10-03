import ServiceManagement
import SwiftUI

struct GeneralView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmReset = false

    private var stats: StatsManager { .shared }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "DotQuit \(short) (\(build))"
    }

    var body: some View {
        @Bindable var settings = SettingsStore.shared

        return PaneScaffold {
            PaneHeader(
                symbol: "gearshape",
                title: "General",
                description: "Startup, privacy and statistics."
            )

            SettingsGroup(footer: loginError) {
                SettingsRow("Launch at login", subtitle: "Start DotQuit automatically when you log in.") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                }
            }

            SettingsGroup("Privacy", footer: "Anonymous counts only — which features get used and how "
                          + "many apps DotQuit closes. No window titles, no keystrokes, no account. "
                          + "Turning this off stops the SDK entirely; nothing is sent.") {
                SettingsRow(
                    "Share anonymous usage diagnostics",
                    subtitle: "Helps work out which features are worth keeping."
                ) {
                    Toggle("", isOn: $settings.isAnalyticsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("Statistics", footer: "Memory figures are each app's physical footprint "
                          + "measured just before it quit.") {
                SettingsRow("Apps closed today") {
                    Text("\(stats.closedToday)").statValue()
                }
                SettingsRow("RAM saved today") {
                    Text(stats.ramSavedTodayText).statValue()
                }
                SettingsRow("Apps closed all time") {
                    Text("\(stats.closedLifetime)").statValue()
                }
                SettingsRow("RAM saved all time") {
                    Text(stats.ramSavedLifetimeText).statValue()
                }
                SettingsActionRow(
                    title: "Reset Statistics…",
                    subtitle: "Set today's and all-time counters back to zero.",
                    symbol: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    confirmReset = true
                }
            }

            SettingsGroup("About", footer: version) {
                SettingsRow("Accessibility", subtitle: "Required for window observation.") {
                    Text(PermissionsManager.shared.isTrusted ? "Granted" : "Not granted")
                        .font(.system(size: 13))
                        .foregroundStyle(PermissionsManager.shared.isTrusted ? DQ.online : .red)
                }
            }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .confirmationDialog(
            "Reset all statistics?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { stats.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today's and all-time counters will be set back to zero. This can't be undone.")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
            // Snap the toggle back to the real system state.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private extension Text {
    func statValue() -> some View {
        font(.system(size: 13, design: .rounded).weight(.medium))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }
}

#Preview {
    GeneralView()
}
