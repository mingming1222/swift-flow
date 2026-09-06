import SwiftUI

/// A screen-space editor surface that owns pointer feedback above the canvas.
/// Coordinates use the canvas's top-left origin and are independent of zoom.
public struct CanvasHoverRegion: Equatable, Sendable {
    public var frame: CGRect
    public var cornerRadius: CGFloat

    public init(frame: CGRect, cornerRadius: CGFloat = 0) {
        self.frame = frame
        self.cornerRadius = cornerRadius
    }

    public func contains(_ point: CGPoint) -> Bool {
        guard !frame.isEmpty, frame.contains(point) else { return false }
        return RoundedRectangle(cornerRadius: max(0, cornerRadius))
            .path(in: frame).contains(point)
    }
}
