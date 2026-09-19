import SwiftUI

/// Geometry information provided to custom edge content closures.
///
/// All point coordinates are in the edge view's **local coordinate system**,
/// where the bounding rect origin is mapped to (0, 0). The `bounds` property
/// retains the original canvas-space rect for placement by the canvas.
public struct EdgeGeometry: Sendable {

    /// Pre-computed edge path in local coordinates.
    public let path: Path

    /// Source handle position in local coordinates.
    public let sourcePoint: CGPoint

    /// Target handle position in local coordinates.
    public let targetPoint: CGPoint

    /// Source handle direction (top/bottom/left/right).
    public let sourcePosition: HandlePosition

    /// Target handle direction (top/bottom/left/right).
    public let targetPosition: HandlePosition

    /// Suggested label placement in local coordinates.
    public let labelPosition: CGPoint

    /// Suggested label rotation angle.
    public let labelAngle: Angle

    /// Canvas-space bounding rect used for symbol placement.
    /// The view's local coordinate system spans (0, 0) to (bounds.width, bounds.height).
    public let bounds: CGRect
}

/// One current geometry per edge: memory stays bounded while nodes move.
/// This cache is owned by the store, never serialized or registered with Undo.
struct EdgeGeometryCache {
    struct Key: Equatable {
        let sourcePoint: CGPoint
        let targetPoint: CGPoint
        let sourcePosition: HandlePosition
        let targetPosition: HandlePosition
        let pathType: EdgePathType
    }

    final class Entry {
        let key: Key
        let geometry: EdgeGeometry
        init(key: Key, geometry: EdgeGeometry) {
            self.key = key
            self.geometry = geometry
        }
    }

    private(set) var entries: [String: Entry] = [:]

    mutating func resolve(edgeID: String, key: Key, build: () -> EdgeGeometry) -> EdgeGeometry {
        if let entry = entries[edgeID], entry.key == key { return entry.geometry }
        let geometry = build()
        entries[edgeID] = Entry(key: key, geometry: geometry)
        return geometry
    }

    mutating func remove(_ edgeID: String) { entries.removeValue(forKey: edgeID) }
    mutating func removeAll() { entries.removeAll() }
    mutating func retainEdges(_ ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
