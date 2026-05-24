import SwiftUI

/// Bundle of policies that govern a single `LiveNode` instance.
///
/// `LiveNode` constructs this internally from its initializer arguments;
/// callers do not build it directly.
public struct LiveNodeConfiguration: Sendable {
    public var mountPolicy: LiveNodeMountPolicy
    public var posterPolicy: LiveNodePosterPolicy

    public init(
        mountPolicy: LiveNodeMountPolicy = .onInteraction,
        posterPolicy: LiveNodePosterPolicy = .automatic
    ) {
        self.mountPolicy = mountPolicy
        self.posterPolicy = posterPolicy
    }

    public static let `default` = LiveNodeConfiguration()
}
