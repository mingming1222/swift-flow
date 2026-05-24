import CoreGraphics

/// Position updates produced by a layout algorithm.
public struct FlowLayoutResult: Sendable, Hashable {

    public var positions: [String: CGPoint]

    public init(positions: [String: CGPoint] = [:]) {
        self.positions = positions
    }

    public var isEmpty: Bool {
        positions.isEmpty
    }
}
