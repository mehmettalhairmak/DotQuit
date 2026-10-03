import AppKit
import Observation

/// Bundle IDs DotQuit leaves alone. Seeded once with a sensible default set so
/// a fresh install doesn't quit the user's chat apps on day one.
@Observable
@MainActor
final class WhitelistManager {
    static let shared = WhitelistManager()

    private let defaults: UserDefaults

    private(set) var bundleIDs: Set<String> {
        didSet { defaults.set(Array(bundleIDs), forKey: DefaultsKey.whitelist) }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: DefaultsKey.whitelistSeeded) {
            bundleIDs = Set(defaults.stringArray(forKey: DefaultsKey.whitelist) ?? [])
        } else {
            // Only seed IDs that are actually installed, so the Whitelist list
            // isn't padded with apps the user doesn't have.
            let installed = AppConstants.defaultWhitelistBundleIDs.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
            bundleIDs = Set(installed)
            defaults.set(Array(installed), forKey: DefaultsKey.whitelist)
            defaults.set(true, forKey: DefaultsKey.whitelistSeeded)
        }
    }

    var count: Int { bundleIDs.count }

    /// `true` when DotQuit must not terminate this app — either the user said
    /// so, or it's one of the system surfaces we never touch.
    func isExempt(_ bundleID: String?) -> Bool {
        guard let bundleID else { return true } // no identity → don't risk it
        return AppConstants.hardExemptBundleIDs.contains(bundleID) || bundleIDs.contains(bundleID)
    }

    /// User-editable membership, ignoring the hard-coded exemptions.
    func isWhitelisted(_ bundleID: String) -> Bool { bundleIDs.contains(bundleID) }

    func isLocked(_ bundleID: String) -> Bool { AppConstants.hardExemptBundleIDs.contains(bundleID) }

    func setWhitelisted(_ whitelisted: Bool, for bundleID: String) {
        guard !isLocked(bundleID) else { return }
        if whitelisted {
            // Only signal a genuine addition, not a re-set of an existing one.
            let (inserted, _) = bundleIDs.insert(bundleID)
            if inserted {
                AnalyticsManager.shared.sendAppSignal(
                    .whitelistAppAdded,
                    bundleID: bundleID
                )
            }
        } else {
            bundleIDs.remove(bundleID)
        }
    }

    func toggle(_ bundleID: String) {
        setWhitelisted(!isWhitelisted(bundleID), for: bundleID)
    }
}
