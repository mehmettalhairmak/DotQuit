import SwiftUI

@main
struct DotQuitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item glyph.
///
/// Dims whenever DotQuit isn't actively watching, so the menu bar always
/// reflects the real state. `MenuBarExtra`'s `image:` initializer would be
/// shorter, but it is static — it can express neither that state nor the
/// icon-style picker in Appearance.
private struct MenuBarLabel: View {
    var body: some View {
        let settings = SettingsStore.shared
        Group {
            if let asset = settings.menuBarIconStyle.assetName {
                Image(asset)
            } else {
                Image(systemName: settings.menuBarIconStyle.symbolName)
            }
        }
        .opacity(settings.isActive ? 1 : 0.4)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared

        // Before anything else, so the launch signal reflects a cold start.
        // No-op when the user has opted out of diagnostics.
        AnalyticsManager.shared.initialize()
        AnalyticsManager.shared.sendLaunchSignal()

        settings.applyTheme()
        settings.applyDockVisibility()

        let permissions = PermissionsManager.shared
        permissions.onGranted = {
            WindowWatcher.shared.syncRunState()
            HotKeyManager.shared.reload()
        }

        HotKeyManager.shared.onTrigger = {
            let settings = SettingsStore.shared
            if settings.isPaused { settings.resume() }
            settings.isEnabled.toggle()
        }
        HotKeyManager.shared.reload()

        WindowWatcher.shared.syncRunState()
        _ = AppRoster.shared

        if !permissions.isTrusted {
            // First run: ask once, and show Settings so the user can see why.
            permissions.requestAccess()
            openSettings()
        }

        Task { await LicenseManager.shared.revalidateStoredKey() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PermissionsManager.shared.refresh()
    }

    func openSettings() {
        SettingsWindowController.shared.show()
    }
}
