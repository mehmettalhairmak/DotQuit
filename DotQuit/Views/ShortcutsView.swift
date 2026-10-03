import AppKit
import SwiftUI

struct ShortcutsView: View {
    private var permissions: PermissionsManager { .shared }

    var body: some View {
        @Bindable var settings = SettingsStore.shared

        PaneScaffold {
            PaneHeader(
                symbol: "command",
                title: "Shortcuts & Permissions",
                description: "DotQuit needs Accessibility access to see when a window closes. "
                    + "It never reads window contents or keystrokes."
            )

            SettingsGroup("System Access", footer: accessFooter) {
                SettingsRow("Accessibility", subtitle: permissions.isTrusted
                    ? "DotQuit can observe window events."
                    : "Without this, DotQuit cannot detect closed windows.") {
                    if permissions.isTrusted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DQ.online)
                            Text("Granted")
                                .font(.system(size: 13))
                                .foregroundStyle(DQ.online)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Button("Open System Settings") {
                                permissions.requestAccess()
                                permissions.openSystemSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                SettingsRow("Watcher", subtitle: "Accessibility observers currently attached.") {
                    Text(WindowWatcher.shared.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup("Keyboard", footer: "Works system-wide while Accessibility access is granted. "
                          + "Press Escape while recording to cancel, or Delete to clear.") {
                SettingsRow("Toggle DotQuit") {
                    ShortcutRecorder(combo: $settings.toggleShortcut)
                }
                SettingsRow("Open Preferences") {
                    KeyCapRow(combo: KeyCombo(keyCode: 43, modifiers: NSEvent.ModifierFlags.command.rawValue))
                }
                SettingsRow("Quit DotQuit") {
                    KeyCapRow(combo: KeyCombo(keyCode: 12, modifiers: NSEvent.ModifierFlags.command.rawValue))
                }
            }
        }
        .onAppear { permissions.refresh() }
    }

    private var accessFooter: String {
        permissions.isTrusted
            ? "Granted in System Settings › Privacy & Security › Accessibility."
            : "Open System Settings › Privacy & Security › Accessibility and switch DotQuit on."
    }
}

/// Click to record, press a combination, Escape to cancel, Delete to clear.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if isRecording {
                Text("Press keys…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80)
            } else {
                KeyCapRow(combo: combo, placeholder: "Not set")
            }

            Button(isRecording ? "Cancel" : "Record") {
                isRecording ? stop() : start()
            }
            .controlSize(.small)

            if combo != nil, !isRecording {
                Button {
                    combo = nil
                    HotKeyManager.shared.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear { stop() }
        .onChange(of: combo) { _, _ in HotKeyManager.shared.reload() }
    }

    private func start() {
        isRecording = true
        // Stop the live hot key so recording ⌥⇧Q doesn't toggle DotQuit.
        HotKeyManager.shared.isSuspended = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil }          // Escape cancels
            if event.keyCode == 51 { combo = nil; stop(); return nil } // Delete clears

            let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Require a modifier, otherwise the shortcut would swallow
            // ordinary typing in every app.
            guard !relevant.isEmpty else { return nil }

            combo = KeyCombo(keyCode: event.keyCode, modifiers: relevant.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyManager.shared.isSuspended = false
    }
}

#Preview {
    ShortcutsView()
}
