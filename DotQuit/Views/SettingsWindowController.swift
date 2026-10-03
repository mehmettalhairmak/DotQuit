import AppKit
import SwiftUI

/// Hosts the settings UI in a window DotQuit owns.
///
/// SwiftUI's `Settings` scene never materialises a window in this app — the
/// `showSettingsWindow:` action reports success but no window is created,
/// verified with a bare `Settings { Text("hello") }`. Owning an `NSWindow`
/// also lets the sidebar run under a transparent title bar, which is what the
/// reference design shows.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        // The autosaved frame can point at a display that has since been
        // unplugged, which would open the window where nobody can reach it.
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !window.isVisible || !onScreen { window.center() }
        window.makeKeyAndOrderFront(nil)

    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.close()
        } else {
            show()
        }
    }

    /// Closing the window must destroy its SwiftUI hierarchy.
    ///
    /// `isReleasedWhenClosed` is false (the controller owns the window), so a
    /// merely-hidden window keeps its views alive — and the status capsule's
    /// repeating pulse animation keeps driving CoreAnimation relayout every
    /// display cycle. Measured at ~16% CPU, forever, in a background agent.
    func windowWillClose(_ notification: Notification) {
        let closing = window
        window = nil
        closing?.delegate = nil
        // Deferred: AppKit is still mid-close on this turn of the run loop.
        DispatchQueue.main.async { closing?.contentViewController = nil }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DotQuit Settings"
        // The sidebar runs edge to edge under the traffic lights.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Required for the sidebar's behind-window vibrancy; the detail column
        // paints its own opaque background.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 880, height: 560)
        window.contentViewController = NSHostingController(rootView: SettingsView())
        // Assigning a hosting controller resizes the window to the view's
        // fitting size, so the intended size has to be applied afterwards.
        window.setContentSize(NSSize(width: 1040, height: 700))
        window.setFrameAutosaveName("DotQuitSettingsWindow")
        window.delegate = self
        return window
    }
}
