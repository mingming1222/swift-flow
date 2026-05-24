/// Computes a new arrangement for a flow graph snapshot.
///
/// Algorithms receive an immutable ``FlowLayoutContext`` and return a
/// ``FlowLayoutResult`` describing the node positions they want to change.
/// The protocol is intentionally small so apps can plug in very different
/// strategies: overlap removal, layered workflow layout, force-directed layout,
/// or app-specific group-aware layout.
public protocol FlowLayoutAlgorithm: Sendable {
    associatedtype Data: Sendable & Hashable

    func layout(context: FlowLayoutContext<Data>) throws -> FlowLayoutResult
}
