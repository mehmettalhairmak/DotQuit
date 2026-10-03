import AppKit
import SwiftUI

/// Design tokens sampled directly from the reference screenshots in
/// `design-examples/`. Dark values are the measured pixels; light values are
/// their counterparts so the Appearance theme switcher stays meaningful.
nonisolated enum DQ {
    /// Geometry measured from the references (all reference pixels ÷ 2).
    enum Metric {
        static let contentWidth: CGFloat = 600
        static let contentTopPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let groupTitleGap: CGFloat = 8

        static let cardRadius: CGFloat = 10
        static let rowInset: CGFloat = 12
        static let rowMinHeight: CGFloat = 40

        static let headerPadding: CGFloat = 16
        static let headerIconSize: CGFloat = 47
        static let headerIconRadius: CGFloat = 12

        static let sidebarWidth: CGFloat = 231
        static let sidebarInset: CGFloat = 12
        static let sidebarRowHeight: CGFloat = 30
        static let sidebarRowRadius: CGFloat = 7

        static let popoverWidth: CGFloat = 278
        static let popoverInset: CGFloat = 14
    }

    static let content = dynamic(dark: 0x1E1E20, light: 0xF2F2F5)
    static let card = dynamic(dark: 0x262628, light: 0xFFFFFF)
    static let cardStroke = dynamic(dark: 0x3A3A3C, light: 0xDEDEE3, darkAlpha: 0.55, lightAlpha: 0.9)
    static let rowDivider = dynamic(dark: 0x3A3A3B, light: 0xE4E4E8)
    static let fieldFill = dynamic(dark: 0x333336, light: 0xFFFFFF)
    static let capsuleFill = dynamic(dark: 0x313135, light: 0xFFFFFF)
    static let keyCapFill = dynamic(dark: 0x3A3A3C, light: 0xF7F7F9)

    /// The header icon tile carries a subtle top-to-bottom gradient.
    static let tileTop = dynamic(dark: 0x424244, light: 0xEFEFF3)
    static let tileBottom = dynamic(dark: 0x343436, light: 0xE3E3E9)

    static let online = dynamic(dark: 0x68CE67, light: 0x30B14F)
    static let paused = dynamic(dark: 0xE2A33C, light: 0xC77F18)

    /// Inset statistics card inside the menu bar popover.
    static let popoverInsetCard = dynamic(dark: 0x2A2B2F, light: 0xEDEDF1)

    static var tileGradient: LinearGradient {
        LinearGradient(colors: [tileTop, tileBottom], startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(
        dark: UInt32,
        light: UInt32,
        darkAlpha: CGFloat = 1,
        lightAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(rgb: dark, alpha: darkAlpha)
                : NSColor(rgb: light, alpha: lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Card chrome

extension View {
    /// The rounded inset-grouped card used for every block of settings.
    func dqCard(radius: CGFloat = DQ.Metric.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(DQ.card, in: shape)
            .overlay { shape.strokeBorder(DQ.cardStroke, lineWidth: 1) }
    }
}

// MARK: - Pane scaffolding

/// Scrolling detail pane: a fixed-width column centred in the content area,
/// matching the 600pt column and 104pt side margins in the references.
struct PaneScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Metric.sectionSpacing) {
                content
            }
            .frame(maxWidth: DQ.Metric.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, DQ.Metric.contentTopPadding)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(DQ.content)
    }
}

/// The large icon + title + description card at the top of every pane.
struct PaneHeader: View {
    var symbol: String
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: DQ.Metric.headerIconRadius, style: .continuous)
                .fill(DQ.tileGradient)
                .frame(width: DQ.Metric.headerIconSize, height: DQ.Metric.headerIconSize)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DQ.Metric.headerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dqCard()
    }
}

/// An optional bold title, a card of hairline-separated rows, and an optional
/// caption underneath — the repeating unit of every settings pane.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Metric.groupTitleGap) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 2)
            }

            _VariadicView.Tree(SeparatedRows()) { content }
                .dqCard()

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 2)
            }
        }
    }
}

/// Interleaves hairlines between a group's children without the call site
/// having to place them. `_VariadicView` is the only way to enumerate
/// ViewBuilder children before macOS 15's `Group(subviews:)`.
private struct SeparatedRows: _VariadicView.UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        return VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last {
                    Rectangle()
                        .fill(DQ.rowDivider)
                        .frame(height: 1)
                        .padding(.horizontal, DQ.Metric.rowInset)
                }
            }
        }
    }
}

/// A card whose rows are built lazily.
///
/// `SettingsGroup` enumerates its children through `_VariadicView`, which
/// forces every row to exist up front — fine for a handful of settings, far
/// too expensive for the few hundred installed apps in the Whitelist pane.
struct LazyRowsCard<Data: RandomAccessCollection, Row: View>: View
where Data.Element: Identifiable {
    var data: Data
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(data) { element in
                row(element)
                if element.id != data.last?.id {
                    Rectangle()
                        .fill(DQ.rowDivider)
                        .frame(height: 1)
                        .padding(.horizontal, DQ.Metric.rowInset)
                }
            }
        }
        .dqCard()
    }
}

/// Title + content + caption, laid out like `SettingsGroup` but with the card
/// supplied by the caller.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Metric.groupTitleGap) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 2)
            }
            content
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 2)
            }
        }
    }
}

/// One line inside a `SettingsGroup`: label, optional explanation, trailing control.
struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, DQ.Metric.rowInset)
        .padding(.vertical, 8)
        .frame(minHeight: DQ.Metric.rowMinHeight)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// A row that behaves like a button but keeps the flat card styling.
struct SettingsActionRow: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var role: ButtonRole?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            .padding(.horizontal, DQ.Metric.rowInset)
            .padding(.vertical, 8)
            .frame(minHeight: DQ.Metric.rowMinHeight)
            .background(isHovering ? Color.primary.opacity(0.05) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Small parts

/// A single key in a shortcut display, as seen in the General reference.
struct KeyCap: View {
    var glyph: String

    var body: some View {
        Text(glyph)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 24, minHeight: 22)
            .padding(.horizontal, 5)
            .background(DQ.keyCapFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

struct KeyCapRow: View {
    var combo: KeyCombo?
    var placeholder = "None"

    var body: some View {
        HStack(spacing: 4) {
            if let combo {
                ForEach(Array(combo.keyCapGlyphs.enumerated()), id: \.offset) { _, glyph in
                    KeyCap(glyph: glyph)
                }
            } else {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Green/amber/grey status dot with a slow halo.
///
/// Backed by CoreAnimation rather than `withAnimation(.repeatForever)`. The
/// SwiftUI version drove a full NSView layout pass every display frame —
/// measured at ~9% CPU on a 120Hz display, and it kept running after the
/// settings window closed. A CALayer animation runs on the render server, so
/// the main thread does nothing once it is started.
struct PulsingDot: NSViewRepresentable {
    var color: Color
    var isPulsing: Bool
    var size: CGFloat = 8

    func makeNSView(context: Context) -> PulseView { PulseView() }

    func updateNSView(_ view: PulseView, context: Context) {
        view.configure(color: NSColor(color), diameter: size, pulsing: isPulsing)
    }

    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PulseView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

/// Layer-backed dot with an expanding halo.
final class PulseView: NSView {
    private let dot = CAShapeLayer()
    private let halo = CAShapeLayer()
    private var diameter: CGFloat = 8
    private var isPulsing = false

    override var intrinsicContentSize: NSSize { NSSize(width: diameter, height: diameter) }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The halo grows past the dot's bounds, so clipping has to stay off.
        layer?.masksToBounds = false
        halo.fillColor = nil
        halo.lineWidth = 1.5
        halo.opacity = 0
        layer?.addSublayer(halo)
        layer?.addSublayer(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(color: NSColor, diameter: CGFloat, pulsing: Bool) {
        let changedSize = diameter != self.diameter
        self.diameter = diameter

        let resolved = color.usingColorSpace(.sRGB) ?? color
        dot.fillColor = resolved.cgColor
        halo.strokeColor = resolved.cgColor

        if changedSize { invalidateIntrinsicContentSize() }
        layoutLayers()

        guard pulsing != isPulsing else { return }
        isPulsing = pulsing
        pulsing ? startPulse() : stopPulse()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        // Both layers share the dot's box; the halo is scaled about its centre.
        let box = CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        let path = CGPath(ellipseIn: CGRect(origin: .zero, size: box.size), transform: nil)

        for layer in [dot, halo] {
            layer.bounds = CGRect(origin: .zero, size: box.size)
            layer.position = CGPoint(x: box.midX, y: box.midY)
            layer.path = path
        }
    }

    private func startPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 2.4

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.6
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // Keeps the halo invisible between repeats rather than snapping back.
        group.isRemovedOnCompletion = false

        halo.add(group, forKey: "pulse")
    }

    private func stopPulse() {
        halo.removeAnimation(forKey: "pulse")
        halo.opacity = 0
    }
}

/// Small pill used for per-app state in the Whitelist list.
struct MiniBadge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
