import CoreGraphics

/// Immutable graph snapshot passed to a layout algorithm.
public struct FlowLayoutContext<Data: Sendable & Hashable>: Sendable, Hashable {

    public let nodes: [FlowNode<Data>]
    public let edges: [FlowEdge]
    public let selectedNodeIDs: Set<String>
    public let scope: FlowLayoutScope
    public let options: FlowLayoutOptions

    public init(
        nodes: [FlowNode<Data>],
        edges: [FlowEdge],
        selectedNodeIDs: Set<String> = [],
        scope: FlowLayoutScope = .all,
        options: FlowLayoutOptions = FlowLayoutOptions()
    ) {
        self.nodes = nodes
        self.edges = edges
        self.selectedNodeIDs = selectedNodeIDs
        self.scope = scope
        self.options = options
    }

    public var nodeLookup: [String: FlowNode<Data>] {
        var lookup: [String: FlowNode<Data>] = [:]
        for node in nodes {
            lookup[node.id] = node
        }
        return lookup
    }

    public var scopedNodeIDs: Set<String> {
        switch scope {
        case .all:
            return Set(nodes.map(\.id))

        case .selected:
            return selectedNodeIDs

        case .nodeIDs(let ids, let includingDescendants):
            guard includingDescendants else { return ids }
            var result = ids
            for id in ids {
                collectDescendants(of: id, into: &result)
            }
            return result

        case .children(let parentID):
            return Set(nodes.filter { $0.parentID == parentID }.map(\.id))
        }
    }

    public var scopedNodes: [FlowNode<Data>] {
        let ids = scopedNodeIDs.subtracting(options.lockedNodeIDs)
        return nodes.filter { ids.contains($0.id) }
    }

    public var scopedEdges: [FlowEdge] {
        let ids = scopedNodeIDs
        return edges.filter { edge in
            ids.contains(edge.sourceNodeID) && ids.contains(edge.targetNodeID)
        }
    }

    public var scopedBounds: CGRect? {
        var iterator = scopedNodes.map(\.frame).makeIterator()
        guard var result = iterator.next() else { return nil }
        while let frame = iterator.next() {
            result = result.union(frame)
        }
        return result
    }

    private func collectDescendants(of nodeID: String, into result: inout Set<String>) {
        for child in nodes where child.parentID == nodeID {
            guard result.insert(child.id).inserted else { continue }
            collectDescendants(of: child.id, into: &result)
        }
    }
}
