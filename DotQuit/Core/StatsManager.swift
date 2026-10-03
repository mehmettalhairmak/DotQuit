import Foundation
import Observation

/// Counts terminations and the memory they freed. Daily figures roll over at
/// midnight; lifetime figures never reset except on explicit user request.
@Observable
@MainActor
final class StatsManager {
    static let shared = StatsManager()

    private let defaults: UserDefaults

    private(set) var closedToday: Int
    private(set) var bytesToday: UInt64
    private(set) var closedLifetime: Int
    private(set) var bytesLifetime: UInt64
    private var day: String

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        day = defaults.string(forKey: DefaultsKey.statsDay) ?? Self.today()
        closedToday = defaults.integer(forKey: DefaultsKey.closedToday)
        bytesToday = UInt64(defaults.double(forKey: DefaultsKey.bytesToday))
        closedLifetime = defaults.integer(forKey: DefaultsKey.closedLifetime)
        bytesLifetime = UInt64(defaults.double(forKey: DefaultsKey.bytesLifetime))
        rollOverIfNeeded()
    }

    // MARK: - Recording

    func recordTermination(freedBytes: UInt64) {
        rollOverIfNeeded()
        closedToday += 1
        bytesToday += freedBytes
        closedLifetime += 1
        bytesLifetime += freedBytes
        persist()
    }

    func resetAll() {
        closedToday = 0
        bytesToday = 0
        closedLifetime = 0
        bytesLifetime = 0
        day = Self.today()
        persist()
    }

    // MARK: - Formatting

    var ramSavedTodayText: String { Self.format(bytesToday) }
    var ramSavedLifetimeText: String { Self.format(bytesLifetime) }

    static func format(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 MB" }
        return Measurement(value: Double(bytes), unit: UnitInformationStorage.bytes)
            .formatted(.byteCount(style: .memory).locale(.current))
    }

    // MARK: - Persistence

    private func rollOverIfNeeded() {
        let current = Self.today()
        guard current != day else { return }
        day = current
        closedToday = 0
        bytesToday = 0
        persist()
    }

    private func persist() {
        defaults.set(day, forKey: DefaultsKey.statsDay)
        defaults.set(closedToday, forKey: DefaultsKey.closedToday)
        defaults.set(Double(bytesToday), forKey: DefaultsKey.bytesToday)
        defaults.set(closedLifetime, forKey: DefaultsKey.closedLifetime)
        defaults.set(Double(bytesLifetime), forKey: DefaultsKey.bytesLifetime)
    }

    private static func today() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
