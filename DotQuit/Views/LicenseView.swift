import AppKit
import SwiftUI

struct LicenseView: View {
    @State private var keyInput = ""
    @State private var isDeactivating = false

    private var license: LicenseManager { .shared }

    var body: some View {
        PaneScaffold {
            PaneHeader(
                symbol: "key",
                title: "License",
                description: "DotQuit is a one-time purchase. Your key is stored in the macOS Keychain "
                    + "and activated with Polar.sh."
            )

            planCard

            if license.isPro {
                activatedDetails
            } else {
                activationForm
                purchaseCard
            }
        }
    }

    // MARK: - Plan

    private var planCard: some View {
        SettingsGroup {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(license.isPro ? AnyShapeStyle(DQ.online.opacity(0.18))
                                        : AnyShapeStyle(DQ.paused.opacity(0.18)))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: license.isPro ? "checkmark.seal.fill" : "clock.badge")
                            .font(.system(size: 17))
                            .foregroundStyle(license.isPro ? DQ.online : DQ.paused)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(license.status.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(license.status.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                MiniBadge(
                    text: license.isPro ? "Verified" : "Trial",
                    tint: license.isPro ? DQ.online : DQ.paused
                )
            }
            .padding(.horizontal, DQ.Metric.rowInset)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Activated

    private var activatedDetails: some View {
        SettingsGroup(
            "Installed License",
            footer: "Deactivating frees this Mac's seat on Polar so you can activate another."
        ) {
            SettingsRow("License key") {
                Text(license.maskedKey ?? "—")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            SettingsRow("This Mac", subtitle: HardwareID.deviceID) {
                Text(HardwareID.deviceLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            SettingsRow("Seats", subtitle: "Your license covers "
                        + "\(AppConstants.Polar.activationLimit) Macs.") {
                Button {
                    isDeactivating = true
                    Task {
                        await license.deactivate()
                        isDeactivating = false
                        keyInput = ""
                    }
                } label: {
                    if isDeactivating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Deactivate")
                    }
                }
                .controlSize(.small)
                .disabled(isDeactivating)
            }
        }
    }

    // MARK: - Activation form

    private var activationForm: some View {
        SettingsGroup("Activate") {
            SettingsRow("License key") {
                TextField("XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(width: 240, height: 26)
                    .background(DQ.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .onChange(of: keyInput) { _, newValue in
                        // Normalise case and strip whitespace, but never
                        // re-group: Polar's own dash layout must survive.
                        let cleaned = LicenseManager.normalized(newValue)
                        if cleaned != newValue { keyInput = cleaned }
                        license.clearMessage()
                    }
                    .onSubmit(activate)
                    .disabled(license.isValidating)
            }

            SettingsRow("Verification", subtitle: verificationSubtitle) {
                Button(action: activate) {
                    if license.isValidating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Activating…")
                        }
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(keyInput.isEmpty || license.isValidating)
            }

            if let message = license.lastMessage {
                HStack(spacing: 7) {
                    Image(systemName: license.lastMessageIsError
                          ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(license.lastMessageIsError ? Color.red : DQ.online)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(license.lastMessageIsError ? Color.red : DQ.online)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DQ.Metric.rowInset)
                .padding(.vertical, 10)
            }
        }
    }

    private var verificationSubtitle: String {
        "Activates this Mac (\(HardwareID.deviceLabel)). Works offline afterwards."
    }

    private var purchaseCard: some View {
        SettingsGroup {
            SettingsActionRow(
                title: "Buy Lifetime License (\(AppConstants.Polar.priceLabel))",
                subtitle: "One payment, \(AppConstants.Polar.activationLimit) Macs, "
                    + "every future update included.",
                symbol: "cart"
            ) {
                NSWorkspace.shared.open(AppConstants.Polar.purchaseURL)
            }
        }
    }

    private func activate() {
        let key = keyInput
        Task { await license.activateLicense(key: key) }
    }
}

#Preview {
    LicenseView()
}
