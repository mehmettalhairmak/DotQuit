import AppKit
import Carbon.HIToolbox

/// Global shortcut for toggling DotQuit. Uses `NSEvent` monitors rather than
/// Carbon hot keys — DotQuit already requires Accessibility access, which is
/// exactly what a global monitor needs, so there's no second permission ask.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var combo: KeyCombo?

    /// Suspended while the user is recording a replacement shortcut.
    var isSuspended = false { didSet { reload() } }

    var onTrigger: (() -> Void)?

    private init() {}

    func reload() {
        teardown()
        guard !isSuspended,
              let combo = SettingsStore.shared.toggleShortcut,
              PermissionsManager.shared.isTrusted else { return }
        self.combo = combo

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            _ = MainActor.assumeIsolated { self?.handle(keyCode: keyCode, modifiers: modifiers) }
        }
        // The global monitor doesn't see events delivered to DotQuit itself.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, modifiers: modifiers) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func teardown() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    @discardableResult
    private func handle(keyCode: UInt16, modifiers: UInt) -> Bool {
        guard let combo, keyCode == combo.keyCode else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let pressed = NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevant)
        guard pressed == combo.flags.intersection(relevant) else { return false }
        onTrigger?()
        return true
    }
}
