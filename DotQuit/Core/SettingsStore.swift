import AppKit
import Observation
import SwiftUI

enum QuitMode: String, CaseIterable, Identifiable, Sendable {
    /// Terminate as soon as any window closes.
    case immediate
    /// Terminate only once the app has no windows left. The safe default.
    case lastWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate: "Quit immediately on close"
        case .lastWindow: "Only quit when last window is closed"
        }
    }

    /// Fits the narrow pop-up button in the Behavior pane.
    var shortTitle: String {
        switch self {
        case .immediate: "Immediate"
        case .lastWindow: "Last Window"
        }
    }

    var explanation: String {
        switch self {
        case .immediate:
            "Quits as soon as nothing is on screen, even if windows are minimized in the Dock."
        case .lastWindow:
            "Quits only when no windows remain at all, including minimized and hidden ones."
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    /// The DotQuit mark: a window card with traffic lights over a Dock dot.
    /// Ships as a template image in the asset catalog, so macOS tints it for
    /// light, dark and wallpaper-tinted menu bars.
    case dotQuit
    case dot, ring, target, power

    var id: String { rawValue }

    /// Asset-catalog name, for styles drawn from artwork rather than SF Symbols.
    var assetName: String? {
        self == .dotQuit ? "MenuBarIcon" : nil
    }

    var symbolName: String {
        switch self {
        case .dotQuit: "macwindow"   // fallback only; `assetName` wins
        case .dot: "circlebadge.fill"
        case .ring: "largecircle.fill.circle"
        case .target: "smallcircle.filled.circle"
        case .power: "power.circle"
        }
    }

    var title: String {
        switch self {
        case .dotQuit: "DotQuit"
        case .dot: "Dot"
        case .ring: "Ring"
        case .target: "Target"
        case .power: "Power"
        }
    }
}

/// A recorded global shortcut. `modifiers` holds raw `NSEvent.ModifierFlags`.
struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt

    static let defaultToggle = KeyCombo(
        keyCode: 12, // Q
        modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// One glyph per key cap, in the order macOS prints modifiers.
    var keyCapGlyphs: [String] {
        var caps: [String] = []
        if flags.contains(.control) { caps.append("\u{2303}") }
        if flags.contains(.option) { caps.append("\u{2325}") }
        if flags.contains(.shift) { caps.append("\u{21E7}") }
        if flags.contains(.command) { caps.append("\u{2318}") }
        caps.append(Self.keyNames[keyCode] ?? "?")
        return caps
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7",
        28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "K", 45: "N", 46: "M", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
        53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
    ]
}

/// User preferences, persisted to `UserDefaults` on write.
@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: DefaultsKey.isEnabled)
            // Flipping the master switch attaches or tears down every
            // accessibility observer, so DotQuit costs nothing when off.
            WindowWatcher.shared.syncRunState()
        }
    }
    var quitMode: QuitMode { didSet { defaults.set(quitMode.rawValue, forKey: DefaultsKey.quitMode) } }
    var optionInverts: Bool { didSet { defaults.set(optionInverts, forKey: DefaultsKey.optionInverts) } }
    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: DefaultsKey.theme)
            applyTheme()
        }
    }
    var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: DefaultsKey.menuBarIconStyle) }
    }
    /// Plays a soft system sound when DotQuit quits an app.
    var soundFeedback: Bool { didSet { defaults.set(soundFeedback, forKey: DefaultsKey.soundFeedback) } }
    /// Force Touch trackpad tap on a successful quit.
    var hapticFeedback: Bool { didSet { defaults.set(hapticFeedback, forKey: DefaultsKey.hapticFeedback) } }
    /// Opt-out for anonymous TelemetryDeck diagnostics.
    var isAnalyticsEnabled: Bool {
        didSet {
            defaults.set(isAnalyticsEnabled, forKey: DefaultsKey.isAnalyticsEnabled)
            AnalyticsManager.shared.applyConsent()
        }
    }
    /// `false` keeps DotQuit a menu bar agent; `true` also shows a Dock icon.
    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: DefaultsKey.showInDock)
            applyDockVisibility()
        }
    }
    var toggleShortcut: KeyCombo? {
        didSet {
            if let toggleShortcut, let data = try? JSONEncoder().encode(toggleShortcut) {
                defaults.set(data, forKey: DefaultsKey.toggleShortcut)
            } else {
                defaults.removeObject(forKey: DefaultsKey.toggleShortcut)
            }
        }
    }
    private(set) var pausedUntil: Date? {
        didSet {
            if let pausedUntil {
                defaults.set(pausedUntil.timeIntervalSinceReferenceDate, forKey: DefaultsKey.pausedUntil)
            } else {
                defaults.removeObject(forKey: DefaultsKey.pausedUntil)
            }
        }
    }

    /// Date of first launch, used to compute trial length.
    let firstLaunchDate: Date

    private var pauseExpiryTask: Task<Void, Never>?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isEnabled = defaults.object(forKey: DefaultsKey.isEnabled) as? Bool ?? true
        quitMode = (defaults.string(forKey: DefaultsKey.quitMode).flatMap(QuitMode.init(rawValue:))) ?? .lastWindow
        optionInverts = defaults.object(forKey: DefaultsKey.optionInverts) as? Bool ?? true
        theme = (defaults.string(forKey: DefaultsKey.theme).flatMap(AppTheme.init(rawValue:))) ?? .auto
        menuBarIconStyle = (defaults.string(forKey: DefaultsKey.menuBarIconStyle)
            .flatMap(MenuBarIconStyle.init(rawValue:))) ?? .dotQuit
        soundFeedback = defaults.object(forKey: DefaultsKey.soundFeedback) as? Bool ?? false
        hapticFeedback = defaults.object(forKey: DefaultsKey.hapticFeedback) as? Bool ?? true
        showInDock = defaults.object(forKey: DefaultsKey.showInDock) as? Bool ?? false
        isAnalyticsEnabled = defaults.object(forKey: DefaultsKey.isAnalyticsEnabled) as? Bool ?? true
        toggleShortcut = (defaults.data(forKey: DefaultsKey.toggleShortcut)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }) ?? .defaultToggle

        if let stamp = defaults.object(forKey: DefaultsKey.pausedUntil) as? TimeInterval {
            let date = Date(timeIntervalSinceReferenceDate: stamp)
            pausedUntil = date > .now ? date : nil
        } else {
            pausedUntil = nil
        }

        if let stamp = defaults.object(forKey: DefaultsKey.firstLaunch) as? TimeInterval {
            firstLaunchDate = Date(timeIntervalSinceReferenceDate: stamp)
        } else {
            firstLaunchDate = .now
            defaults.set(firstLaunchDate.timeIntervalSinceReferenceDate, forKey: DefaultsKey.firstLaunch)
        }

        schedulePauseExpiry()
    }

    // MARK: - Derived state

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > .now
    }

    /// The single question the watcher asks before acting.
    var isActive: Bool { isEnabled && !isPaused }

    var statusText: String {
        if !isEnabled { return "Off" }
        if isPaused { return "Paused" }
        return "Active"
    }

    // MARK: - Actions

    func pause(for duration: TimeInterval) {
        pausedUntil = Date(timeIntervalSinceNow: duration)
        schedulePauseExpiry()
    }

    func resume() {
        pauseExpiryTask?.cancel()
        pauseExpiryTask = nil
        pausedUntil = nil
    }

    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }

    /// `LSUIElement` is set in Info.plist, so DotQuit launches as an agent.
    /// Switching to `.regular` at runtime is what puts it back in the Dock.
    func applyDockVisibility() {
        guard let app = NSApp else { return }
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        if policy == .regular { app.activate(ignoringOtherApps: true) }
    }

    /// Fired by the watcher once an app has actually quit.
    func playTerminationFeedback() {
        if hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        if soundFeedback {
            NSSound(named: "Pop")?.play()
        }
    }

    /// Clears `pausedUntil` the moment the pause lapses so the UI flips back to
    /// "Active" without polling.
    private func schedulePauseExpiry() {
        pauseExpiryTask?.cancel()
        guard let pausedUntil, pausedUntil > .now else { return }
        let interval = pausedUntil.timeIntervalSinceNow
        pauseExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.pausedUntil = nil
        }
    }
}
