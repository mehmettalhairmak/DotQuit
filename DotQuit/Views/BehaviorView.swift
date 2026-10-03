import SwiftUI

struct BehaviorView: View {
    var body: some View {
        @Bindable var settings = SettingsStore.shared

        PaneScaffold {
            PaneHeader(
                symbol: "slider.horizontal.3",
                title: "Behavior",
                description: "Decide when DotQuit steps in after you click a window's red close button."
            )

            SettingsGroup(footer: pauseFooter) {
                SettingsRow("DotQuit", subtitle: settings.isActive ? "Watching close buttons" : statusDetail) {
                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsRow("Mode", subtitle: settings.quitMode.explanation) {
                    Picker("", selection: $settings.quitMode) {
                        ForEach(QuitMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup("While Running", footer: "DotQuit only ever sends a normal quit request. If an app "
                          + "has unsaved work it shows its own “Save changes?” sheet — cancel it and the app stays open.") {
                SettingsRow(
                    "Hold Option (⌥) to invert",
                    subtitle: "Holding ⌥ as you close flips the whitelist for that one window: "
                        + "a whitelisted app quits, any other app is left running."
                ) {
                    Toggle("", isOn: $settings.optionInverts)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsRow("Play a sound on quit", subtitle: "A soft pop when an app is closed.") {
                    Toggle("", isOn: $settings.soundFeedback)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsRow("Haptic feedback", subtitle: "Taps a Force Touch trackpad on each quit.") {
                    Toggle("", isOn: $settings.hapticFeedback)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("Protected", footer: "Menu bar items, helpers and background daemons are never "
                          + "touched — only regular desktop apps are considered.") {
                SettingsRow("Never force-quit", subtitle: "kill(9) is never used, under any setting.") {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(DQ.online)
                }
                SettingsRow("Finder and system surfaces", subtitle: "Permanently exempt.") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusDetail: String {
        let settings = SettingsStore.shared
        if settings.isPaused { return "Paused — windows are being ignored" }
        return "Turned off"
    }

    private var pauseFooter: String? {
        let settings = SettingsStore.shared
        guard settings.isPaused, let until = settings.pausedUntil else { return nil }
        return "Paused until \(until.formatted(date: .omitted, time: .shortened))."
    }
}

#Preview {
    BehaviorView()
}
