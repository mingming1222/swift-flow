import CoreGraphics

/// Shared options that algorithms can honor without changing their public API.
public struct FlowLayoutOptions: Sendable, Hashable {

    /// Desired space between neighboring node frames.
    public var spacing: CGSize

    /// Extra space algorithms should keep around scoped bounds or groups.
    public var padding: CGFloat

    /// Nodes that should remain fixed even when they are inside the scope.
    public var lockedNodeIDs: Set<String>

    /// Whether algorithms should prefer small moves over full rearrangement.
    public var preservesRelativePositions: Bool

    public init(
        spacing: CGSize = CGSize(width: 24, height: 24),
        padding: CGFloat = 24,
        lockedNodeIDs: Set<String> = [],
        preservesRelativePositions: Bool = true
    ) {
        self.spacing = spacing
        self.padding = padding
        self.lockedNodeIDs = lockedNodeIDs
        self.preservesRelativePositions = preservesRelativePositions
    }
}
