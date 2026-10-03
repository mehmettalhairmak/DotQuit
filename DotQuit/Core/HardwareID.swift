import Foundation
import IOKit

/// A stable per-Mac identifier, used as the activation condition so that
/// reinstalling DotQuit — or restoring it from a backup — reuses the same
/// Polar activation instead of burning another seat.
nonisolated enum HardwareID {
    /// `IOPlatformUUID` from `IOPlatformExpertDevice`. It survives OS
    /// reinstalls and is stable for the life of the machine.
    static let deviceID: String = platformUUID() ?? fallbackID()

    /// Shown in the Polar dashboard so the customer can tell their Macs apart.
    static var deviceLabel: String {
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return name.isEmpty ? "Mac" : name
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        guard let uuid = property.takeRetainedValue() as? String, !uuid.isEmpty else { return nil }
        return uuid
    }

    /// If IOKit ever refuses, fall back to a UUID generated once and kept in
    /// the Keychain, so the device identity is still stable across launches.
    private static func fallbackID() -> String {
        let account = "hardwareFallbackID"
        if let existing = Keychain.get(account) { return existing }
        let generated = UUID().uuidString
        Keychain.set(generated, for: account)
        return generated
    }
}
