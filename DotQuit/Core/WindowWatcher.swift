import AppKit
import ApplicationServices
import Darwin
import Observation
import OSLog

private let log = Logger(subsystem: AppConstants.bundleID, category: "WindowWatcher")

/// Per-application accessibility bookkeeping. One of these is passed to the
/// AXObserver as its `refcon`, so every callback knows which process it came
/// from without having to interrogate a possibly-dead element.
private final class AppObservation {
    let pid: pid_t
    let bundleID: String?
    let element: AXUIElement
    var observer: AXObserver?
    weak var watcher: WindowWatcher?

    init(pid: pid_t, bundleID: String?, element: AXUIElement, watcher: WindowWatcher) {
        self.pid = pid
        self.bundleID = bundleID
        self.element = element
        self.watcher = watcher
    }

    func invalidate() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
    }

    deinit { invalidate() }
}

/// AXObserver callbacks arrive as C function pointers, so this must be a
/// non-capturing, non-isolated function. The observer's run loop source is
/// attached to the main run loop, so we are provably on the main actor here.
private nonisolated func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let context = Unmanaged<AppObservation>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        context.watcher?.handle(notification: name, element: element, context: context)
    }
}

/// Watches every regular GUI app for window destruction and, when an app is
/// left with nothing on screen, asks it politely to quit.
@Observable
@MainActor
final class WindowWatcher {
    static let shared = WindowWatcher()

    private(set) var isRunning = false

    @ObservationIgnored private var observations: [pid_t: AppObservation] = [:]
    @ObservationIgnored private var pendingChecks: [pid_t: Task<Void, Never>] = [:]
    /// pid → what we measured just before asking it to quit. The stat is only
    /// banked once the process actually dies, so a cancelled "Save changes?"
    /// sheet never inflates the numbers.
    @ObservationIgnored private var pendingTerminations: [pid_t: PendingTermination] = [:]
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []

    private let settings = SettingsStore.shared
    private let whitelist = WhitelistManager.shared
    private let stats = StatsManager.shared

    private init() {}

    // MARK: - Lifecycle

    /// Starts or stops observation to match the current permission and
    /// enablement state. Safe to call as often as you like.
    func syncRunState() {
        let shouldRun = PermissionsManager.shared.isTrusted && SettingsStore.shared.isEnabled
        if shouldRun { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        subscribeToWorkspace()
        for app in NSWorkspace.shared.runningApplications { attach(to: app) }
        log.info("Watching \(self.observations.count) applications")
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver(_:))
        workspaceTokens.removeAll()

        pendingChecks.values.forEach { $0.cancel() }
        pendingChecks.removeAll()
        observations.values.forEach { $0.invalidate() }
        observations.removeAll()
        pendingTerminations.removeAll()
    }

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        func observe(_ name: Notification.Name, _ body: @escaping (NSRunningApplication) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                MainActor.assumeIsolated { body(app) }
            }
            workspaceTokens.append(token)
        }

        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            // Freshly launched apps are often not AX-responsive yet.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(750))
                self?.attach(to: app)
            }
        }
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            // Doubles as a retry for apps whose first attach attempt failed and
            // catches processes that only became `.regular` after launch.
            self?.attach(to: app)
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.handleTermination(of: app.processIdentifier)
        }
    }

    // MARK: - Attachment

    private func attach(to app: NSRunningApplication, retriesRemaining: Int = 5) {
        let pid = app.processIdentifier
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
        // Guardrail: only desktop GUI apps. Menu bar items (.accessory) and
        // daemons (.prohibited) are never observed, let alone terminated.
        guard app.activationPolicy == .regular else { return }
        guard !AppConstants.hardExemptBundleIDs.contains(app.bundleIdentifier ?? "") else { return }

        if let existing = observations[pid] {
            // Already watching — pick up any windows opened in the meantime.
            syncWindows(for: existing)
            return
        }

        let element = AXUIElementCreateApplication(pid)

        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer else {
            scheduleAttachRetry(app, retriesRemaining)
            return
        }

        let context = AppObservation(
            pid: pid,
            bundleID: app.bundleIdentifier,
            element: element,
            watcher: self
        )
        context.observer = observer

        let refcon = Unmanaged.passUnretained(context).toOpaque()
        let added = AXObserverAddNotification(
            observer,
            element,
            kAXWindowCreatedNotification as CFString,
            refcon
        )

        // An app that is still launching answers `.cannotComplete` here: its
        // accessibility server isn't up yet. Treating that as success would
        // leave the app permanently unwatched, so retry instead of recording
        // a half-attached observation.
        guard added == .success || added == .notificationAlreadyRegistered else {
            log.debug("windowCreated registration deferred for pid \(pid): \(added.rawValue)")
            scheduleAttachRetry(app, retriesRemaining)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observations[pid] = context
        syncWindows(for: context)
    }

    private func scheduleAttachRetry(_ app: NSRunningApplication, _ retriesRemaining: Int) {
        guard retriesRemaining > 0 else {
            log.debug("giving up attaching to pid \(app.processIdentifier)")
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !app.isTerminated else { return }
            self?.attach(to: app, retriesRemaining: retriesRemaining - 1)
        }
    }

    /// Subscribes to every currently-open window we aren't already watching.
    /// Re-registering an existing one is harmless — AX answers
    /// `.notificationAlreadyRegistered`.
    private func syncWindows(for context: AppObservation) {
        for window in Self.axWindows(of: context.element) {
            track(window: window, in: context)
        }
    }

    private func detach(pid: pid_t) {
        pendingChecks.removeValue(forKey: pid)?.cancel()
        observations.removeValue(forKey: pid)?.invalidate()
    }

    /// Subscribes to a single window's destruction.
    ///
    /// Filtered by subrole rather than by `kAXCloseButtonAttribute`: that
    /// attribute answers `kAXErrorNoValue` for perfectly ordinary windows
    /// (panels, sheets, windows mid-layout), which silently left them
    /// untracked. Subrole is stable and still excludes HUDs and tool palettes.
    private func track(window: AXUIElement, in context: AppObservation) {
        guard let observer = context.observer, Self.isTrackableWindow(window) else { return }
        AXObserverAddNotification(
            observer,
            window,
            kAXUIElementDestroyedNotification as CFString,
            Unmanaged.passUnretained(context).toOpaque()
        )
    }

    // MARK: - Notification handling

    fileprivate func handle(notification: String, element: AXUIElement, context: AppObservation) {
        switch notification {
        case kAXWindowCreatedNotification:
            track(window: element, in: context)
        case kAXUIElementDestroyedNotification:
            // We never listen for Cmd+W or any key event: a destroyed window
            // element is the one signal that means "this window is gone",
            // whether it was the red dot, a tab close, or the app itself.
            scheduleEvaluation(for: context)
        default:
            break
        }
    }

    private func scheduleEvaluation(for context: AppObservation) {
        guard settings.isActive else { return }

        // Sampled now, not after the debounce — the user may have let go of
        // Option by the time we actually decide.
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        let pid = context.pid
        let bundleID = context.bundleID

        pendingChecks[pid]?.cancel()
        pendingChecks[pid] = Task { [weak self] in
            // Let the window teardown settle. Entering or leaving fullscreen
            // destroys and recreates a window, and we must not act on the gap.
            try? await Task.sleep(for: AppConstants.terminationDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingChecks[pid] = nil
            self.evaluate(pid: pid, fallbackBundleID: bundleID, optionHeld: optionHeld)
        }
    }

    // MARK: - Decision

    private func evaluate(pid: pid_t, fallbackBundleID: String?, optionHeld: Bool) {
        guard settings.isActive else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            detach(pid: pid)
            return
        }
        guard app.activationPolicy == .regular else { return }

        guard let bundleID = app.bundleIdentifier ?? fallbackBundleID,
              !AppConstants.hardExemptBundleIDs.contains(bundleID) else { return }

        // Holding Option flips the whitelist decision for this one close:
        // a whitelisted app quits, a normal app is spared.
        let inverted = settings.optionInverts && optionHeld
        if inverted {
            AnalyticsManager.shared.send(.optionInvertUsed)
        }
        guard whitelist.isWhitelisted(bundleID) == inverted else { return }

        // Non-negotiable: if anything of this app is still on screen, it stays.
        guard Self.onScreenWindowCount(pid: pid) == 0 else { return }

        if settings.quitMode == .lastWindow {
            // Stricter still — minimized and hidden windows count as "open",
            // so an app parked in the Dock is never quit out from under the user.
            guard Self.closableWindowCount(of: AXUIElementCreateApplication(pid)) == 0 else { return }
        }

        terminate(app, bundleID: bundleID)
    }

    private func terminate(_ app: NSRunningApplication, bundleID: String) {
        let pid = app.processIdentifier
        let footprint = Self.memoryFootprint(pid: pid)

        // Gentle only. If there are unsaved changes macOS puts up its own
        // "Save changes?" sheet; if the user cancels, the app simply lives on
        // and we never hear a termination notification.
        guard app.terminate() else {
            log.debug("terminate() refused for \(bundleID, privacy: .public)")
            return
        }
        log.info("Asked \(bundleID, privacy: .public) to quit")

        pendingTerminations[pid] = PendingTermination(bundleID: bundleID, footprint: footprint)
        Task { [weak self] in
            // Don't credit a quit that happens minutes later for other reasons.
            try? await Task.sleep(for: .seconds(120))
            self?.pendingTerminations[pid] = nil
        }
    }

    private func handleTermination(of pid: pid_t) {
        detach(pid: pid)
        guard let pending = pendingTerminations.removeValue(forKey: pid) else { return }
        stats.recordTermination(freedBytes: pending.footprint)
        settings.playTerminationFeedback()
        AnalyticsManager.shared.sendAppSignal(
            .appTerminatedByDotQuit,
            bundleID: pending.bundleID
        )
    }

    private struct PendingTermination {
        let bundleID: String
        let footprint: UInt64
    }

    // MARK: - Window inspection

    /// On-screen, normal-layer windows belonging to `pid`.
    private static func onScreenWindowCount(pid: pid_t) -> Int {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        return list.filter { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid else { return false }
            // Layer 0 is the normal document window layer; menus, popovers and
            // status items live above it.
            guard info[kCGWindowLayer as String] as? Int == 0 else { return false }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { return false }
            // Filters out the 1pt proxy windows some frameworks leave behind.
            return width >= 60 && height >= 60
        }.count
    }

    private static func axWindows(of appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    /// Standard windows and dialogs — including minimized ones, which the
    /// CoreGraphics on-screen list deliberately omits.
    private static func closableWindowCount(of appElement: AXUIElement) -> Int {
        axWindows(of: appElement).filter(isTrackableWindow).count
    }

    /// A window the user can close and that counts towards "is anything left".
    private static func isTrackableWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        guard result == .success, let subrole = value as? String else {
            // Subrole unreadable: be permissive. Over-tracking only costs a
            // debounced re-check; under-tracking means DotQuit never fires.
            return true
        }
        return subrole == "AXStandardWindow" || subrole == "AXDialog"
    }

    // MARK: - Memory

    /// Physical memory footprint of `pid`, as Activity Monitor reports it.
    private static func memoryFootprint(pid: pid_t) -> UInt64 {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, buffer)
            }
        }
        guard result == 0, info.ri_phys_footprint > 0 else {
            return AppConstants.fallbackFootprintBytes
        }
        return info.ri_phys_footprint
    }
}
