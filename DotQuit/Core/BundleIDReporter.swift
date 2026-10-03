import CryptoKit
import Foundation

/// Decides how an app's bundle identifier may appear in telemetry.
///
/// Knowing *which* apps DotQuit closes is the whole point of the
/// `app_terminated_by_dotquit` signal, but a bundle identifier can also be a
/// private fact — `com.acmebank.internal.trading-desk` names an employer and a
/// project. Public, widely-installed apps are reported verbatim; everything
/// else is reduced to a salted digest that still counts distinct apps without
/// naming them.
nonisolated enum BundleIDReporter {
    static func reportable(_ bundleID: String) -> String {
        let normalized = bundleID.lowercased()

        // Apple reserves com.apple.*, so these can never be a private app.
        if normalized.hasPrefix("com.apple.") { return normalized }
        if publicBundleIDs.contains(normalized) { return normalized }

        return "private." + digest(of: normalized)
    }

    /// Salted SHA-256, truncated. Stable for a given app so distinct-app
    /// counts still work, but not reversible without already knowing the
    /// identifier you're looking for.
    private static func digest(of bundleID: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(AppConstants.Analytics.salt.utf8))
        hasher.update(data: Data(bundleID.utf8))
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    /// Widely distributed consumer and developer apps. Membership here only
    /// decides whether a name is sent in the clear — adding to it is a
    /// privacy decision, so keep it to software anyone can download.
    private static let publicBundleIDs: Set<String> = [
        // Browsers
        "com.google.chrome", "com.google.chrome.canary", "org.mozilla.firefox",
        "com.brave.browser", "com.microsoft.edgemac", "company.thebrowser.browser",
        "com.operasoftware.opera", "org.chromium.chromium", "com.vivaldi.vivaldi",
        // Communication
        "com.tinyspeck.slackmacgap", "com.hnc.discord", "us.zoom.xos",
        "com.microsoft.teams2", "com.microsoft.teams", "ru.keepcoder.telegram",
        "org.telegram.desktop", "desktop.whatsapp", "net.whatsapp.whatsapp",
        "org.whispersystems.signal-desktop", "com.readdle.smailpro",
        // Media
        "com.spotify.client", "org.videolan.vlc", "com.colliderli.iina",
        "com.plexapp.plex", "tv.parsec.www",
        // Productivity
        "notion.id", "md.obsidian", "com.culturedcode.thingsmac",
        "com.flexibits.fantastical2.mac", "net.shinyfrog.bear",
        "com.linear", "com.todoist.mac.todoist", "com.evernote.evernote",
        "com.microsoft.word", "com.microsoft.excel", "com.microsoft.powerpoint",
        "com.microsoft.onenote.mac", "com.microsoft.outlook",
        // Developer tools
        "com.microsoft.vscode", "com.visualstudio.code.oss",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.webstorm",
        "com.jetbrains.goland", "com.jetbrains.rider", "com.jetbrains.appcode",
        "com.googlecode.iterm2", "dev.warp.warp-stable", "com.github.atom",
        "com.sublimetext.4", "com.sublimemerge", "com.postmanlabs.mac",
        "com.docker.docker", "com.figma.desktop", "com.sketch.app",
        "com.panic.nova", "com.panic.transmit", "com.github.githubclient",
        "com.tower3.tower", "com.getinsomnia.insomnia",
        // Utilities
        "com.agilebits.onepassword7", "com.1password.1password",
        "com.getdropbox.dropbox", "com.raycast.macos", "com.runningwithcrayons.alfred",
        "com.valvesoftware.steam", "com.adobe.photoshop", "com.adobe.illustrator",
        "com.serif.affinityphoto2", "com.serif.affinitydesigner2",
    ]
}
