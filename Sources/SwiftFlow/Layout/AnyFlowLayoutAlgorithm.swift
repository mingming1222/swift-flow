/// Type-erased layout algorithm for storing app-selected strategies.
public struct AnyFlowLayoutAlgorithm<Data: Sendable & Hashable>: FlowLayoutAlgorithm {

    private let body: @Sendable (FlowLayoutContext<Data>) throws -> FlowLayoutResult

    public init<Algorithm: FlowLayoutAlgorithm>(_ algorithm: Algorithm) where Algorithm.Data == Data {
        body = { context in
            try algorithm.layout(context: context)
        }
    }

    public init(
        _ body: @escaping @Sendable (FlowLayoutContext<Data>) throws -> FlowLayoutResult
    ) {
        self.body = body
    }

    public func layout(context: FlowLayoutContext<Data>) throws -> FlowLayoutResult {
        try body(context)
    }
}
