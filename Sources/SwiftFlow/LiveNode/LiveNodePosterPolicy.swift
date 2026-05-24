/// Timing policy for poster updates.
public enum LiveNodePosterCaptureTiming: Sendable, Hashable {
    /// SwiftFlow requests a poster update at the default lifecycle point.
    case automatic

    /// The hosted view is responsible for requesting or writing a poster.
    case manual
}

/// Policy that controls when SwiftFlow updates a LiveNode poster.
public struct LiveNodePosterPolicy: Sendable, Hashable {
    public var initialCapture: LiveNodePosterCaptureTiming
    public var interactionEndCapture: LiveNodePosterCaptureTiming

    public init(
        initialCapture: LiveNodePosterCaptureTiming = .automatic,
        interactionEndCapture: LiveNodePosterCaptureTiming = .automatic
    ) {
        self.initialCapture = initialCapture
        self.interactionEndCapture = interactionEndCapture
    }

    public static let automatic = LiveNodePosterPolicy()

    public static let manual = LiveNodePosterPolicy(
        initialCapture: .manual,
        interactionEndCapture: .manual
    )
}
