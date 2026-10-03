import Foundation
import Observation

enum LicenseStatus: Equatable, Sendable {
    case trial(daysRemaining: Int)
    case trialExpired
    case pro

    var isPro: Bool { self == .pro }

    var title: String {
        switch self {
        case .pro: "DotQuit Pro — Lifetime"
        case .trial: "Free Trial"
        case .trialExpired: "Trial Expired"
        }
    }

    var detail: String {
        switch self {
        case .pro: "Activated on this Mac. Thanks for supporting DotQuit."
        case .trial(let days): "\(days) day\(days == 1 ? "" : "s") remaining."
        case .trialExpired: "Activate a license to keep using Pro features."
        }
    }

    /// Short tier label for the sidebar capsule.
    var tierLabel: String {
        switch self {
        case .pro: "Lifetime License"
        case .trial(let days): "Free • \(days) day\(days == 1 ? "" : "s") left"
        case .trialExpired: "Free • Trial ended"
        }
    }
}

/// Validates lifetime licenses against Polar.sh and exposes the Pro flag the
/// rest of the app gates on.
@Observable
@MainActor
final class LicenseManager {
    static let shared = LicenseManager()

    private(set) var status: LicenseStatus = .trial(daysRemaining: AppConstants.trialLengthDays)
    private(set) var storedKey: String?
    private(set) var activationID: String?
    private(set) var isValidating = false

    /// Last activation outcome, for the inline label under the key field.
    private(set) var lastMessage: String?
    private(set) var lastMessageIsError = false

    private let session: URLSession
    private let defaults: UserDefaults

    private init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        // The key itself is a secret and lives in the Keychain; the Pro flag is
        // mirrored into UserDefaults so the UI is correct at launch without
        // waiting on a Keychain prompt or a network round trip.
        storedKey = Keychain.get(DefaultsKey.licenseKey)
        activationID = Keychain.get(DefaultsKey.activationID)
        refreshStatus()
    }

    /// The single place feature gating should consult.
    var isPro: Bool { status.isPro }

    /// `DQ-••••-••••-XXXX` — enough for the customer to recognise which key is
    /// installed without putting the whole secret on screen.
    var maskedKey: String? {
        guard let storedKey else { return nil }
        let tail = storedKey.filter { $0.isLetter || $0.isNumber }.suffix(4)
        guard tail.count == 4 else { return nil }
        return "DQ-••••-••••-\(tail)"
    }

    // MARK: - Status

    private func refreshStatus() {
        if storedKey != nil, defaults.bool(forKey: DefaultsKey.isProActivated) {
            status = .pro
            return
        }
        let elapsed = Calendar.current.dateComponents(
            [.day],
            from: SettingsStore.shared.firstLaunchDate,
            to: .now
        ).day ?? 0
        let remaining = AppConstants.trialLengthDays - elapsed
        status = remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }

    // MARK: - Activation

    /// Activates `key` for this Mac against Polar.
    ///
    /// The hardware UUID is sent as an activation condition so repeated
    /// installs on the same machine reuse one seat.
    @discardableResult
    func activateLicense(key rawKey: String) async -> (success: Bool, message: String) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard Self.looksLikeKey(key) else {
            return finish(false, "Enter the license key from your Polar receipt.")
        }

        isValidating = true
        defer { isValidating = false }

        var request = URLRequest(url: AppConstants.Polar.activateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(ActivateRequest(
                key: key,
                organizationId: AppConstants.Polar.organizationID,
                label: HardwareID.deviceLabel,
                conditions: ["device_id": HardwareID.deviceID]
            ))
        } catch {
            return finish(false, "Couldn't build the activation request.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return finish(false, "Couldn't reach Polar: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            return finish(false, "Invalid license key")
        }

        switch http.statusCode {
        case 200:
            let payload = try? JSONDecoder().decode(ActivationResponse.self, from: data)
            // A key can be activated but revoked/disabled on Polar's side.
            if let state = payload?.licenseKey?.status, state != "granted" {
                return finish(false, "This license is \(state). Contact support.")
            }
            apply(key: key, activationID: payload?.id)
            AnalyticsManager.shared.send(.licenseActivated)
            return finish(true, "License activated on this Mac.")

        case 403, 422:
            // 403 is a refused activation (seats exhausted, key revoked) and
            // 422 a rejected body; prefer Polar's own wording when it gives one.
            let detail = Self.serverMessage(from: data)
            return finish(false, detail ?? "Activation limit reached: maximum "
                          + "\(AppConstants.Polar.activationLimit) Macs")

        default:
            // 404 is Polar's answer for a key it has never issued.
            return finish(false, "Invalid license key")
        }
    }

    /// Releases this Mac's seat on Polar before clearing the local record, so
    /// the customer gets the activation back.
    func deactivate() async {
        if let storedKey, let activationID {
            var request = URLRequest(url: AppConstants.Polar.deactivateURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(DeactivateRequest(
                key: storedKey,
                organizationId: AppConstants.Polar.organizationID,
                activationId: activationID
            ))
            _ = try? await session.data(for: request)
        }
        clearLocalLicense()
        lastMessage = nil
        lastMessageIsError = false
    }

    /// Re-checks a stored key in the background — catches refunds and
    /// revocations without ever blocking launch.
    func revalidateStoredKey() async {
        guard let storedKey else { return }

        var request = URLRequest(url: AppConstants.Polar.validateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ValidateRequest(
            key: storedKey,
            organizationId: AppConstants.Polar.organizationID,
            activationId: activationID,
            conditions: ["device_id": HardwareID.deviceID]
        ))

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return // Network trouble must never downgrade a paying customer.
        }

        switch http.statusCode {
        case 200:
            let payload = try? JSONDecoder().decode(ValidationResponse.self, from: data)
            if let state = payload?.status, state != "granted" { clearLocalLicense() }
        case 403, 404:
            clearLocalLicense()
        default:
            break // Treat 5xx and anything unexpected as "still valid".
        }
    }

    // MARK: - Persistence

    private func apply(key: String, activationID: String?) {
        storedKey = key
        self.activationID = activationID
        Keychain.set(key, for: DefaultsKey.licenseKey)
        Keychain.set(activationID, for: DefaultsKey.activationID)
        defaults.set(true, forKey: DefaultsKey.isProActivated)
        refreshStatus()
    }

    private func clearLocalLicense() {
        Keychain.set(nil, for: DefaultsKey.licenseKey)
        Keychain.set(nil, for: DefaultsKey.activationID)
        defaults.set(false, forKey: DefaultsKey.isProActivated)
        storedKey = nil
        activationID = nil
        refreshStatus()
    }

    private func finish(_ success: Bool, _ message: String) -> (success: Bool, message: String) {
        lastMessage = message
        lastMessageIsError = !success
        return (success, message)
    }

    func clearMessage() {
        lastMessage = nil
        lastMessageIsError = false
    }

    // MARK: - Key handling

    /// Polar issues keys as dash-separated alphanumeric groups, optionally with
    /// a product prefix. Deliberately permissive: the server is the authority,
    /// this only catches obviously empty or pasted-wrong input.
    static func looksLikeKey(_ key: String) -> Bool {
        guard key.count >= 8 else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Normalises pasted input without re-grouping it — Polar's own grouping
    /// must survive intact, so only case and stray whitespace are touched.
    static func normalized(_ input: String) -> String {
        input.uppercased().filter { !$0.isWhitespace }
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(ServerError.self, from: data) else { return nil }
        if let detail = payload.detail, !detail.isEmpty, detail != "Not found" { return detail }
        if let error = payload.error, !error.isEmpty, error != "ResourceNotFound" { return error }
        return nil
    }

    // MARK: - Wire types

    private struct ActivateRequest: Encodable {
        let key: String
        let organizationId: String
        let label: String
        let conditions: [String: String]

        enum CodingKeys: String, CodingKey {
            case key, label, conditions
            case organizationId = "organization_id"
        }
    }

    private struct DeactivateRequest: Encodable {
        let key: String
        let organizationId: String
        let activationId: String

        enum CodingKeys: String, CodingKey {
            case key
            case organizationId = "organization_id"
            case activationId = "activation_id"
        }
    }

    private struct ValidateRequest: Encodable {
        let key: String
        let organizationId: String
        let activationId: String?
        let conditions: [String: String]

        enum CodingKeys: String, CodingKey {
            case key, conditions
            case organizationId = "organization_id"
            case activationId = "activation_id"
        }
    }

    private struct ActivationResponse: Decodable {
        let id: String?
        let licenseKey: LicenseKeyPayload?

        enum CodingKeys: String, CodingKey {
            case id
            case licenseKey = "license_key"
        }
    }

    private struct ValidationResponse: Decodable {
        let status: String?
    }

    private struct LicenseKeyPayload: Decodable {
        let status: String?
        let limitActivations: Int?

        enum CodingKeys: String, CodingKey {
            case status
            case limitActivations = "limit_activations"
        }
    }

    /// Polar returns `{"error": "...", "detail": "..."}` for most failures and
    /// FastAPI's `{"detail": [{"msg": "..."}]}` for body validation, so
    /// `detail` has to be decoded as either shape.
    private struct ServerError: Decodable {
        private struct Item: Decodable { let msg: String? }

        let error: String?
        let detail: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try? container.decodeIfPresent(String.self, forKey: .error)
            if let text = try? container.decodeIfPresent(String.self, forKey: .detail) {
                detail = text
            } else if let items = try? container.decodeIfPresent([Item].self, forKey: .detail) {
                detail = items.compactMap(\.msg).first
            } else {
                detail = nil
            }
        }

        private enum CodingKeys: String, CodingKey { case error, detail }
    }
}
