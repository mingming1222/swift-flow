import Observation
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

/// Live input geometry. Pass the source itself through the drawing hierarchy;
/// only pointer handlers and the hover tracker should read its regions.
@MainActor @Observable
public final class CanvasHoverRegionSource {
    public private(set) var regions: [CanvasHoverRegion] = []

    public init() {}

    public func update(_ regions: [CanvasHoverRegion]) {
        guard self.regions != regions else { return }
        self.regions = regions
    }

    public func contains(_ point: CGPoint) -> Bool {
        regions.contains { $0.contains(point) }
    }
}
