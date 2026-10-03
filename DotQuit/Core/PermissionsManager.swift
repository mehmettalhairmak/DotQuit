import ApplicationServices
import AppKit
import Observation

/// Tracks the Accessibility (AXIsProcessTrusted) grant. Without it DotQuit has
/// no way to observe other apps' windows, so this gates the whole feature.
@Observable
@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()

    private(set) var isTrusted: Bool
    private var pollTask: Task<Void, Never>?

    /// Called when the grant flips to `true`, so the watcher can start.
    var onGranted: (() -> Void)?

    private init() {
        isTrusted = AXIsProcessTrusted()
        if !isTrusted { startPolling() }
    }

    /// Shows the system's "grant Accessibility access" alert.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted { startPolling() }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted {
            pollTask?.cancel()
            pollTask = nil
            onGranted?()
        }
    }

    /// There is no notification for the grant, so poll — but only while
    /// untrusted, which is a transient first-run state. Once granted the task
    /// cancels and DotQuit returns to zero idle CPU.
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}
