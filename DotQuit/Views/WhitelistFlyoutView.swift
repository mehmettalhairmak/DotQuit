import AppKit
import SwiftUI

/// Two-tier whitelist picker, hosted in the left-anchored flyout panel.
struct WhitelistFlyoutView: View {
    @Namespace private var tierNamespace

    private var whitelist: WhitelistManager { .shared }
    private var roster: AppRoster { .shared }

    // MARK: - Sizing
    //
    // The panel must know its height before it is shown, and a ScrollView has
    // no intrinsic height to ask for. Deriving it from the row count keeps the
    // panel correctly sized on first paint with no resize flicker.

    static let width: CGFloat = 264
    static let maxHeight: CGFloat = 340

    private static let rowHeight: CGFloat = 27
    private static let tierLabelHeight: CGFloat = 19
    private static let dividerHeight: CGFloat = 13
    private static let outerPadding: CGFloat = 8

    static func preferredHeight(candidates: Int, whitelisted: Int) -> CGFloat {
        let rows = CGFloat(max(candidates, 1) + max(whitelisted, 1))
        let natural = outerPadding
            + tierLabelHeight * 2
            + dividerHeight
            + rows * rowHeight
        return min(max(natural, 110), maxHeight)
    }

    // MARK: - Data

    /// Running apps not yet whitelisted, with the app the user was last
    /// working in pinned to the top.
    var candidates: [RosterApp] {
        let whitelisted = whitelist.bundleIDs
        return roster.runningApps
            .filter { !whitelisted.contains($0.bundleID) }
            .sorted { lhs, rhs in
                let lhsActive = lhs.bundleID == roster.frontmostBundleID
                let rhsActive = rhs.bundleID == roster.frontmostBundleID
                if lhsActive != rhsActive { return lhsActive }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var protectedApps: [RosterApp] {
        whitelist.bundleIDs
            .map { roster.app(for: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                tierLabel("Running Apps")

                if candidates.isEmpty {
                    placeholder("No other apps running")
                } else {
                    ForEach(candidates) { app in
                        WhitelistPickerRow(
                            app: app,
                            isWhitelisted: false,
                            isActiveApp: app.bundleID == roster.frontmostBundleID,
                            namespace: tierNamespace
                        ) {
                            whitelist.setWhitelisted(true, for: app.bundleID)
                        }
                    }
                }

                Rectangle()
                    .fill(DQ.rowDivider)
                    .frame(height: 1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)

                tierLabel("Whitelisted")

                if protectedApps.isEmpty {
                    placeholder("No apps whitelisted")
                } else {
                    ForEach(protectedApps) { app in
                        WhitelistPickerRow(
                            app: app,
                            isWhitelisted: true,
                            isActiveApp: false,
                            namespace: tierNamespace
                        ) {
                            whitelist.setWhitelisted(false, for: app.bundleID)
                        }
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(VisualEffectBackdrop(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: whitelist.bundleIDs)
        .contentShape(.rect)
        // Keeps the flyout alive while the pointer is inside it.
        .onHover { WhitelistFlyoutController.shared.flyoutHover($0) }
        .task { roster.refresh() }
    }

    private func tierLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
            .padding(.top, 2)
            .padding(.bottom, 3)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
    }
}

/// One app row. Tapping moves it across the divider; `matchedGeometryEffect`
/// makes that read as motion rather than a disappear-and-reappear.
private struct WhitelistPickerRow: View {
    var app: RosterApp
    var isWhitelisted: Bool
    var isActiveApp: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: AppRoster.shared.icon(for: app))
                    .resizable()
                    .frame(width: 18, height: 18)

                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isActiveApp {
                    Text("Active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DQ.online)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DQ.online.opacity(0.16), in: Capsule())
                }

                Spacer(minLength: 6)

                Image(systemName: isWhitelisted ? "xmark.circle.fill" : "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isWhitelisted ? AnyShapeStyle(.secondary) : AnyShapeStyle(DQ.online))
                    .opacity(isHovering ? 1 : 0.5)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.09) : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .matchedGeometryEffect(id: app.bundleID, in: namespace)
        .help(isWhitelisted
              ? "\(app.name) is never quit automatically — click to remove"
              : "Click to stop DotQuit quitting \(app.name)")
    }
}

/// Native vibrancy behind the flyout.
struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
