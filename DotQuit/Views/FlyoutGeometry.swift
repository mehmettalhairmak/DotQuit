import CoreGraphics
import Foundation

/// Placement maths for the whitelist flyout, kept free of AppKit objects so it
/// can be reasoned about and tested directly.
nonisolated enum FlyoutGeometry {
    /// Gap between the popover and the panel. Zero by design: a visible seam
    /// is a dead zone the pointer can cross, which would dismiss the flyout
    /// mid-travel.
    static let gap: CGFloat = 0
    /// Keeps the panel clear of the screen edges.
    static let margin: CGFloat = 8

    /// Preferred placement: immediately left of the popover, with its top edge
    /// level with the trigger row.
    ///
    /// - Parameters:
    ///   - anchor: the trigger row, in screen coordinates (bottom-left origin).
    ///   - host: the popover window's frame, in screen coordinates.
    ///   - visible: the target screen's `visibleFrame`.
    /// - Returns: a frame guaranteed to sit inside `visible`.
    static func frame(
        anchor: CGRect,
        host: CGRect,
        visible: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: horizontalOrigin(host: host, visible: visible, width: width),
            y: verticalOrigin(anchor: anchor, visible: visible, height: height),
            width: width,
            height: height
        )
    }

    /// Left of the popover; flipped to the right when the menu bar item sits
    /// near the left screen edge; clamped if neither side fits.
    static func horizontalOrigin(host: CGRect, visible: CGRect, width: CGFloat) -> CGFloat {
        let left = host.minX - width - gap
        if left >= visible.minX + margin { return left }

        let right = host.maxX + gap
        if right + width <= visible.maxX - margin { return right }

        return max(visible.minX + margin, visible.maxX - width - margin)
    }

    /// Top of the panel level with the top of the trigger row, pushed back
    /// inside the screen if the panel is taller than the space below.
    static func verticalOrigin(anchor: CGRect, visible: CGRect, height: CGFloat) -> CGFloat {
        var y = anchor.maxY - height
        if y + height > visible.maxY - margin { y = visible.maxY - margin - height }
        if y < visible.minY + margin { y = visible.minY + margin }
        return y
    }
}
