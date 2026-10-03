import AppKit
import Observation
import UniformTypeIdentifiers

struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let path: String

    var id: String { bundleID }
}

/// Enumerates installed applications for the Whitelist list. The scan touches
/// the filesystem, so it runs off the main actor and is only triggered when
/// the Whitelist pane is actually shown.
@Observable
@MainActor
final class AppDirectory {
    static let shared = AppDirectory()

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false

    private var iconCache: [String: NSImage] = [:]

    private nonisolated static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    private init() {}

    func loadIfNeeded() async {
        guard apps.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        // Running apps are folded in so anything launched from an unusual
        // location still shows up in the list.
        let running: [InstalledApp] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { return nil }
            return InstalledApp(
                bundleID: bundleID,
                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                path: url.path
            )
        }

        let scanned = await Task.detached(priority: .utility) {
            Self.scanDisk()
        }.value

        var merged: [String: InstalledApp] = [:]
        for app in scanned + running { merged[app.bundleID] = app }
        // Anything the user already whitelisted must stay listed even if the
        // app has since been deleted, otherwise they can't un-whitelist it.
        for bundleID in WhitelistManager.shared.bundleIDs where merged[bundleID] == nil {
            merged[bundleID] = InstalledApp(bundleID: bundleID, name: bundleID, path: "")
        }

        apps = merged.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func add(bundleAt url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let app = InstalledApp(bundleID: bundleID, name: name, path: url.path)

        if let index = apps.firstIndex(where: { $0.bundleID == bundleID }) {
            apps[index] = app
        } else {
            apps.append(app)
            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        WhitelistManager.shared.setWhitelisted(true, for: bundleID)
    }

    func icon(for app: InstalledApp) -> NSImage {
        if let cached = iconCache[app.bundleID] { return cached }
        let image: NSImage
        if !app.path.isEmpty, FileManager.default.fileExists(atPath: app.path) {
            image = NSWorkspace.shared.icon(forFile: app.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        image.size = NSSize(width: 32, height: 32)
        iconCache[app.bundleID] = image
        return image
    }

    private nonisolated static func scanDisk() -> [InstalledApp] {
        let fileManager = FileManager.default
        var found: [InstalledApp] = []

        for directory in searchPaths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = directory + "/" + entry
                guard let bundle = Bundle(path: path),
                      let bundleID = bundle.bundleIdentifier,
                      !AppConstants.hardExemptBundleIDs.contains(bundleID) else { continue }
                let info = bundle.infoDictionary
                // Skip background-only bundles; they are never termination targets.
                if info?["LSUIElement"] as? Bool == true || info?["LSBackgroundOnly"] as? Bool == true {
                    continue
                }
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? String(entry.dropLast(4))
                found.append(InstalledApp(bundleID: bundleID, name: name, path: path))
            }
        }
        return found
    }
}
