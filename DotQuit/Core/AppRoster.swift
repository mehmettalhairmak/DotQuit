import AppKit
import Observation
import UniformTypeIdentifiers

/// One application as the whitelist picker sees it.
struct RosterApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    /// Path to the app bundle, used for the Finder icon. Nil if the app isn't
    /// installed any more (a whitelist entry can outlive its app).
    let bundlePath: String?

    var id: String { bundleID }
}

/// Live inventory of regular GUI apps, for the popover's whitelist picker.
///
/// Driven entirely by `NSWorkspace` notifications — no polling — so it costs
/// nothing while the popover is closed. Replaces the old FrontmostAppTracker,
/// which observed the same notification for a subset of this.
@Observable
@MainActor
final class AppRoster {
    static let shared = AppRoster()

    /// Regular, user-facing apps currently running, alphabetically. Excludes
    /// DotQuit itself and the permanently-exempt system surfaces, neither of
    /// which can be whitelisted.
    private(set) var runningApps: [RosterApp] = []

    /// The app the user was last actually working in.
    ///
    /// `NSWorkspace.frontmostApplication` is useless once the popover opens —
    /// that makes DotQuit frontmost — so DotQuit is never recorded here.
    private(set) var frontmostBundleID: String?

    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var resolvedCache: [String: RosterApp] = [:]

    private init() {
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        for name: Notification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            tokens.append(token)
        }
    }

    /// Rebuilds the roster. Cheap (a few dozen processes) and also called when
    /// the popover appears, in case a notification was missed.
    func refresh() {
        var seen: Set<String> = []
        var apps: [RosterApp] = []

        for app in NSWorkspace.shared.runningApplications {
            // Only desktop GUI apps: .accessory menu bar items and
            // .prohibited daemons are never termination targets, so offering
            // to whitelist them would be meaningless.
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != AppConstants.bundleID,
                  !AppConstants.hardExemptBundleIDs.contains(bundleID),
                  seen.insert(bundleID).inserted else { continue }

            apps.append(RosterApp(
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                bundlePath: app.bundleURL?.path
            ))
        }

        runningApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.activationPolicy == .regular,
           let bundleID = front.bundleIdentifier,
           bundleID != AppConstants.bundleID {
            frontmostBundleID = bundleID
        }
    }

    /// Display info for any bundle ID, running or not — a whitelist entry can
    /// outlive the app that created it.
    func app(for bundleID: String) -> RosterApp {
        if let running = runningApps.first(where: { $0.bundleID == bundleID }) { return running }
        if let cached = resolvedCache[bundleID] { return cached }

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let resolved = RosterApp(
            bundleID: bundleID,
            name: url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID,
            bundlePath: url?.path
        )
        resolvedCache[bundleID] = resolved
        return resolved
    }

    func icon(for app: RosterApp) -> NSImage {
        if let cached = iconCache[app.bundleID] { return cached }

        let image: NSImage
        if let path = app.bundlePath, FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        image.size = NSSize(width: 18, height: 18)
        iconCache[app.bundleID] = image
        return image
    }
}
