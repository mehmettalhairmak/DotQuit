import Foundation

/// Static configuration that has no business living in `UserDefaults`.
nonisolated enum AppConstants {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.mehmettalhairmak.DotQuit"

    /// Apps DotQuit must never terminate, regardless of the user's whitelist.
    /// Finder is `.regular` but quitting it degrades the desktop; the rest are
    /// system surfaces whose lifecycle belongs to macOS.
    static let hardExemptBundleIDs: Set<String> = [
        bundleID,
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
    ]

    /// Shipped whitelist — chat/music apps users expect to keep running.
    static let defaultWhitelistBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.tinyspeck.slackmacgap",
        "desktop.WhatsApp",
        "net.whatsapp.WhatsApp",
        "com.apple.mail",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
    ]

    /// Grace period between the last window dying and termination. Long enough
    /// that a fullscreen transition (which destroys and recreates the window)
    /// settles before we count windows.
    static let terminationDelay: Duration = .milliseconds(600)

    /// Conservative stand-in when `proc_pid_rusage` can't read a process.
    static let fallbackFootprintBytes: UInt64 = 150 * 1024 * 1024

    static let trialLengthDays = 7

    nonisolated enum Analytics {
        static let appID = "2F73DEAB-49DF-42CA-8B45-E26EF48E2EE4"

        /// Mixed into the user-identifier hash so DotQuit's hashes can't be
        /// matched against another app's. It also salts the bundle-ID digest
        /// below. Changing it resets every anonymous user identity, so treat
        /// it as permanent.
        ///
        /// Note this ships inside the binary and is therefore extractable —
        /// it defends against correlation by a third party holding the
        /// hashes, not against someone who has the app.
        static let salt = "dq_telemetry_salt_2026_x89a1b2c"
    }

    nonisolated enum Polar {
        static let organizationID = "9be38072-76d3-434e-94ed-2a82fcc629d9"

        // The customer-portal endpoints, NOT the bare /v1/license-keys/* ones.
        // Those are organization-side and answer 401 without a Polar access
        // token — shipping such a token inside the app would hand every
        // downloader control of the whole Polar organization. The payloads are
        // identical; these accept the customer's own key as the credential.
        private static let base = "https://api.polar.sh/v1/customer-portal/license-keys"
        static let activateURL = URL(string: "\(base)/activate")!
        static let validateURL = URL(string: "\(base)/validate")!
        static let deactivateURL = URL(string: "\(base)/deactivate")!

        static let purchaseURL = URL(
            string: "https://buy.polar.sh/polar_cl_tfdIyrLDQxAYfrf82gdBeNrCVPXjyA5CqFSO90Eitzf"
        )!

        /// Seats sold with the lifetime licence.
        static let activationLimit = 2

        static let priceLabel = "$2.99"
    }
}

nonisolated enum DefaultsKey {
    static let isEnabled = "isEnabled"
    static let quitMode = "quitMode"
    static let optionInverts = "optionInverts"
    static let pausedUntil = "pausedUntil"
    static let theme = "theme"
    static let menuBarIconStyle = "menuBarIconStyle"
    static let soundFeedback = "soundFeedback"
    static let hapticFeedback = "hapticFeedback"
    static let showInDock = "showInDock"
    static let isAnalyticsEnabled = "isAnalyticsEnabled"
    static let toggleShortcut = "toggleShortcut"
    static let whitelist = "whitelistBundleIDs"
    static let whitelistSeeded = "whitelistSeeded"
    static let statsDay = "statsDay"
    static let closedToday = "closedToday"
    static let bytesToday = "bytesToday"
    static let closedLifetime = "closedLifetime"
    static let bytesLifetime = "bytesLifetime"
    static let firstLaunch = "firstLaunchDate"
    static let licenseKey = "licenseKey"
    static let activationID = "licenseActivationID"
    static let isProActivated = "isProActivated"
}
