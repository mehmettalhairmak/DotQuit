import Foundation
import TelemetryDeck

/// Every analytics signal DotQuit can emit. Keeping them in one enum means the
/// full list of what leaves the machine is readable in a single place.
enum AnalyticsSignal: String {
    case appLaunched = "app_launched"
    case appTerminatedByDotQuit = "app_terminated_by_dotquit"
    case whitelistAppAdded = "whitelist_app_added"
    case licenseActivated = "license_activated"
    case optionInvertUsed = "option_invert_used"
}

/// The only place in DotQuit that imports TelemetryDeck.
///
/// Nothing is initialised and nothing is transmitted unless the user has left
/// "Share anonymous usage diagnostics" on; turning it off tears the SDK down
/// rather than just muting it.
@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private(set) var isInitialized = false

    private init() {}

    /// Called once at launch. A no-op when the user has opted out.
    func initialize() {
        guard SettingsStore.shared.isAnalyticsEnabled, !isInitialized else { return }
        // `salt` is a `let` on Config, so it has to go through the
        // initializer rather than being assigned afterwards.
        let config = TelemetryDeck.Config(
            appID: AppConstants.Analytics.appID,
            salt: AppConstants.Analytics.salt
        )
        // The SDK defaults to flushing every 10s, which wakes an otherwise
        // idle menu bar agent six times a minute and shows up as measurable
        // idle CPU. DotQuit emits a handful of signals a day, so batch far
        // less often; anything pending is cached to disk and sent later.
        config.transmitInterval = 120
        // The SDK's session tracker writes to UserDefaults on a 1-second
        // repeating timer, which alone cost ~0.4% idle CPU in a menu bar agent
        // that is meant to sit at zero. Session length here is just uptime, so
        // it buys nothing; our own signals are unaffected.
        config.sessionStatsEnabled = false
        TelemetryDeck.initialize(config: config)
        isInitialized = true
    }

    /// Queues a signal. TelemetryDeck batches and uploads on its own
    /// background queue, caches when offline and retries later, so this never
    /// blocks the caller and never surfaces an error.
    func send(_ signal: AnalyticsSignal, parameters: [String: String] = [:]) {
        guard SettingsStore.shared.isAnalyticsEnabled, isInitialized else { return }
        TelemetryDeck.signal(signal.rawValue, parameters: parameters)
    }

    /// Sends a signal about another application, with its bundle identifier
    /// passed through `BundleIDReporter` first.
    ///
    /// Call sites use this rather than `send(_:parameters:)` so a raw bundle
    /// identifier can't reach telemetry by accident.
    func sendAppSignal(_ signal: AnalyticsSignal, bundleID: String) {
        send(signal, parameters: ["bundle_id": BundleIDReporter.reportable(bundleID)])
    }

    /// Reacts to the opt-out toggle flipping at runtime.
    func applyConsent() {
        if SettingsStore.shared.isAnalyticsEnabled {
            initialize()
        } else if isInitialized {
            TelemetryDeck.terminate()
            isInitialized = false
        }
    }

    // MARK: - Launch context

    func sendLaunchSignal() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        send(.appLaunched, parameters: [
            "macos_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "app_version": Self.appVersion,
        ])
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
