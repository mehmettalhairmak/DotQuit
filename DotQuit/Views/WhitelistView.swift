import SwiftUI
import UniformTypeIdentifiers

struct WhitelistView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All Apps"
        case whitelisted = "Whitelisted"

        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var isImporting = false

    private var directory: AppDirectory { .shared }
    private var whitelist: WhitelistManager { .shared }

    private var visibleApps: [InstalledApp] {
        directory.apps.filter { app in
            if filter == .whitelisted, !whitelist.isWhitelisted(app.bundleID) { return false }
            let query = search.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(query)
                || app.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        PaneScaffold {
            PaneHeader(
                symbol: "square.grid.2x2",
                title: "Whitelist",
                description: "Choose which apps DotQuit leaves running when their last window closes."
            )

            SettingsGroup {
                SettingsRow("Filtering") {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                SettingsRow("Search") {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("App name or bundle ID", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 240, height: 24)
                    .background(DQ.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            SettingsSection(
                filter == .whitelisted ? "Whitelisted Apps" : "Allowed Apps",
                footer: "\(whitelist.count) app\(whitelist.count == 1 ? "" : "s") whitelisted. "
                    + "Protected apps are system surfaces DotQuit never quits."
            ) {
                if directory.isLoading && directory.apps.isEmpty {
                    SettingsGroup {
                        SettingsRow("Scanning applications…") {
                            ProgressView().controlSize(.small)
                        }
                    }
                } else if visibleApps.isEmpty {
                    SettingsGroup {
                        SettingsRow(
                            search.isEmpty ? "No apps to show" : "No apps match “\(search)”",
                            subtitle: search.isEmpty ? nil : "Try a different name or bundle identifier."
                        )
                    }
                } else {
                    LazyRowsCard(data: visibleApps) { app in
                        AppToggleRow(app: app)
                    }
                }
            }

            SettingsGroup {
                SettingsActionRow(
                    title: "Add Application…",
                    subtitle: "Pick an app bundle that isn't in the list.",
                    symbol: "plus"
                ) {
                    isImporting = true
                }
                SettingsActionRow(
                    title: "Rescan Applications",
                    subtitle: "Re-read /Applications and currently running apps.",
                    symbol: "arrow.clockwise"
                ) {
                    Task { await directory.reload() }
                }
            }
        }
        .task { await directory.loadIfNeeded() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                directory.add(bundleAt: url)
            }
        }
    }
}

private struct AppToggleRow: View {
    var app: InstalledApp

    private var whitelist: WhitelistManager { .shared }

    var body: some View {
        let locked = whitelist.isLocked(app.bundleID)
        let on = whitelist.isWhitelisted(app.bundleID)

        HStack(spacing: 10) {
            Image(nsImage: AppDirectory.shared.icon(for: app))
                .resizable()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 14))
                Text(app.bundleID)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if locked {
                MiniBadge(text: "Protected", tint: .secondary)
            } else if on {
                MiniBadge(text: "Never quit", tint: DQ.online)
            }

            Toggle("", isOn: Binding(
                get: { on },
                set: { whitelist.setWhitelisted($0, for: app.bundleID) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(locked)
        }
        .padding(.horizontal, DQ.Metric.rowInset)
        .padding(.vertical, 7)
        .frame(minHeight: DQ.Metric.rowMinHeight)
    }
}

#Preview {
    WhitelistView()
}
