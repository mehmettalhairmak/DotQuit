import AppKit
import SwiftUI

/// Owns the left-anchored whitelist flyout panel.
///
/// The panel is a `.nonactivatingPanel` child of the menu bar popover. That
/// matters: the popover dismisses itself when it resigns key, so a flyout that
/// took focus would tear down its own parent the moment you clicked a row.
@MainActor
final class WhitelistFlyoutController: NSObject, NSWindowDelegate {
    static let shared = WhitelistFlyoutController()

    /// Delay before opening, so sweeping the pointer past the row on the way
    /// somewhere else doesn't flash the panel open.
    private static let openDelay: Duration = .milliseconds(140)
    /// Hysteresis: long enough to cross the seam between popover and panel
    /// diagonally without the panel closing underneath the pointer.
    private static let closeDelay: Duration = .milliseconds(300)

    private var panel: NSPanel?
    private weak var hostWindow: NSWindow?
    private var hostObservers: [NSObjectProtocol] = []

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    private var pointerInTrigger = false
    private var pointerInFlyout = false

    private var anchorInScreen: NSRect = .zero

    private override init() { super.init() }

    var isOpen: Bool { panel != nil }

    // MARK: - Hover coordination

    /// Click fallback for anyone who can't hold a steady hover.
    func togglePinned(anchor: NSRect, host: NSWindow?) {
        if isOpen {
            close()
        } else {
            hostWindow = host
            anchorInScreen = anchor
            pointerInTrigger = true
            cancelClose()
            present()
        }
    }

    /// Called by the "Smart Whitelist" row as the pointer enters and leaves.
    func triggerHover(_ inside: Bool, anchor: NSRect, host: NSWindow?) {
        pointerInTrigger = inside
        anchorInScreen = anchor
        if inside {
            hostWindow = host
            cancelClose()
            guard panel == nil else { return }
            openTask?.cancel()
            openTask = Task { [weak self] in
                try? await Task.sleep(for: Self.openDelay)
                guard !Task.isCancelled, let self, self.pointerInTrigger else { return }
                self.present()
            }
        } else {
            openTask?.cancel()
            openTask = nil
            scheduleClose()
        }
    }

    /// Called by the flyout's own content as the pointer enters and leaves.
    func flyoutHover(_ inside: Bool) {
        pointerInFlyout = inside
        if inside { cancelClose() } else { scheduleClose() }
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerInTrigger, !self.pointerInFlyout else { return }
            self.close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    // MARK: - Panel lifecycle

    private func present() {
        guard panel == nil, let host = hostWindow else { return }

        let content = WhitelistFlyoutView()
        let height = WhitelistFlyoutView.preferredHeight(
            candidates: content.candidates.count,
            whitelisted: content.protectedApps.count
        )

        let targetFrame = Self.frame(anchor: anchorInScreen, host: host, height: height)
        let panel = NSPanel(
            contentRect: targetFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(rootView: content)
        // Assigning a hosting controller resizes the window to the SwiftUI
        // fitting size, and a ScrollView reports zero there — so the intended
        // frame has to be reapplied afterwards.
        panel.setFrame(targetFrame, display: false)
        panel.delegate = self

        // As a child window it follows the popover and is torn down with it.
        host.addChildWindow(panel, ordered: .above)
        panel.order(.above, relativeTo: host.windowNumber)

        self.panel = panel
        observeHost(host)
    }

    /// Tears the panel down completely rather than hiding it, so no SwiftUI
    /// view tree is left alive driving animations off screen.
    func close() {
        openTask?.cancel(); openTask = nil
        closeTask?.cancel(); closeTask = nil
        pointerInTrigger = false
        pointerInFlyout = false

        stopObservingHost()

        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.parent?.removeChildWindow(panel)
        panel.contentViewController = nil
        panel.orderOut(nil)
    }

    // MARK: - Host observation

    private func observeHost(_ host: NSWindow) {
        stopObservingHost()
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            let token = center.addObserver(forName: name, object: host, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
            hostObservers.append(token)
        }
    }

    private func stopObservingHost() {
        hostObservers.forEach(NotificationCenter.default.removeObserver(_:))
        hostObservers.removeAll()
    }

    // MARK: - Geometry

    private static func frame(anchor: NSRect, host: NSWindow, height: CGFloat) -> NSRect {
        let screen = host.screen ?? NSScreen.main ?? NSScreen.screens[0]
        return FlyoutGeometry.frame(
            anchor: anchor,
            host: host.frame,
            visible: screen.visibleFrame,
            width: WhitelistFlyoutView.width,
            height: height
        )
    }
}

/// Reports a SwiftUI view's frame in screen coordinates, plus the window it
/// lives in. SwiftUI's own `.global` space is top-left origin and
/// window-relative, so the conversion is done in AppKit where it is exact.
struct AnchorReader: NSViewRepresentable {
    var onChange: (NSRect, NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorReaderView {
        AnchorReaderView(onChange: onChange)
    }

    func updateNSView(_ view: AnchorReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }
}

final class AnchorReaderView: NSView {
    var onChange: (NSRect, NSWindow?) -> Void

    init(onChange: @escaping (NSRect, NSWindow?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    override func layout() {
        super.layout()
        report()
    }

    func report() {
        guard let window else { return }
        onChange(window.convertToScreen(convert(bounds, to: nil)), window)
    }
}
