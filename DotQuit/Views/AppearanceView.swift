import SwiftUI

struct AppearanceView: View {
    var body: some View {
        @Bindable var settings = SettingsStore.shared

        PaneScaffold {
            PaneHeader(
                symbol: "circle.lefthalf.filled",
                title: "Appearance",
                description: "Adjust how DotQuit looks in the menu bar and on your desktop."
            )

            SettingsGroup(footer: "The menu bar icon switches to a dotted outline whenever "
                          + "DotQuit is off or paused.") {
                SettingsRow("Appearance") {
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                SettingsRow("Menu bar icon") {
                    Picker("", selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbolName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup("Desktop", footer: "DotQuit is a menu bar agent by default. Showing it in the "
                          + "Dock also gives it a normal app menu.") {
                SettingsRow(
                    "Hide from Dock",
                    subtitle: "Run as a menu bar agent only."
                ) {
                    Toggle("", isOn: Binding(
                        get: { !settings.showInDock },
                        set: { settings.showInDock = !$0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                SettingsRow("Preview") {
                    HStack(spacing: 10) {
                        Image(systemName: settings.isActive
                              ? settings.menuBarIconStyle.symbolName
                              : "circle.dotted")
                        .font(.system(size: 14))
                        Text(settings.isActive ? "Active" : settings.statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DQ.keyCapFill, in: Capsule())
                }
            }
        }
    }
}

#Preview {
    AppearanceView()
}
