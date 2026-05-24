import CoreGraphics

public extension FlowStore {

    func layoutContext(
        scope: FlowLayoutScope = .all,
        options: FlowLayoutOptions = FlowLayoutOptions()
    ) -> FlowLayoutContext<Data> {
        FlowLayoutContext(
            nodes: nodes,
            edges: edges,
            selectedNodeIDs: selectedNodeIDs,
            scope: scope,
            options: options
        )
    }

    @discardableResult
    func layout<Algorithm: FlowLayoutAlgorithm>(
        using algorithm: Algorithm,
        scope: FlowLayoutScope = .all,
        options: FlowLayoutOptions = FlowLayoutOptions(),
        animation: FlowAnimation? = nil
    ) throws -> FlowLayoutResult where Algorithm.Data == Data {
        let result = try algorithm.layout(
            context: layoutContext(scope: scope, options: options)
        )
        applyLayout(result, animation: animation)
        return result
    }

    func applyLayout(
        _ result: FlowLayoutResult,
        animation: FlowAnimation? = nil
    ) {
        guard !result.isEmpty else { return }

        if let animation {
            setNodePositions(result.positions, animation: animation)
            return
        }

        var startPositions: [String: CGPoint] = [:]
        for nodeID in result.positions.keys {
            guard let node = nodeLookup[nodeID] else { continue }
            startPositions[nodeID] = node.position
        }

        beginInteractiveUpdates()
        for (nodeID, position) in result.positions {
            moveNode(nodeID, to: position)
        }
        endInteractiveUpdates()

        completeMoveNodes(from: startPositions)
    }
}
