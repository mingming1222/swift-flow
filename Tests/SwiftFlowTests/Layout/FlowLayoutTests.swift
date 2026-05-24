import CoreGraphics
import Testing
@testable import SwiftFlow

@Suite("FlowLayout Tests")
@MainActor
struct FlowLayoutTests {

    @Test("Context resolves selected scope and locked nodes")
    func contextResolvesSelectedScopeAndLockedNodes() {
        let nodes = [
            FlowNode(id: "a", position: .zero, data: "A"),
            FlowNode(id: "b", position: CGPoint(x: 100, y: 0), data: "B"),
            FlowNode(id: "c", position: CGPoint(x: 200, y: 0), data: "C"),
        ]
        let context = FlowLayoutContext(
            nodes: nodes,
            edges: [],
            selectedNodeIDs: ["a", "b"],
            scope: .selected,
            options: FlowLayoutOptions(lockedNodeIDs: ["b"])
        )

        #expect(context.scopedNodeIDs == ["a", "b"])
        #expect(context.scopedNodes.map(\.id) == ["a"])
    }

    @Test("Context includes descendants when requested")
    func contextIncludesDescendantsWhenRequested() {
        let nodes = [
            FlowNode(id: "group", position: .zero, data: "Group", acceptsChildren: true),
            FlowNode(id: "child", position: CGPoint(x: 20, y: 20), data: "Child", parentID: "group"),
            FlowNode(id: "grandchild", position: CGPoint(x: 30, y: 30), data: "Grandchild", parentID: "child"),
            FlowNode(id: "outside", position: CGPoint(x: 300, y: 0), data: "Outside"),
        ]
        let context = FlowLayoutContext(
            nodes: nodes,
            edges: [],
            scope: .nodeIDs(["group"], includingDescendants: true)
        )

        #expect(context.scopedNodeIDs == ["group", "child", "grandchild"])
        #expect(context.scopedNodes.map(\.id) == ["group", "child", "grandchild"])
    }

    @Test("Context filters scoped edges")
    func contextFiltersScopedEdges() {
        let nodes = [
            FlowNode(id: "a", position: .zero, data: "A"),
            FlowNode(id: "b", position: CGPoint(x: 100, y: 0), data: "B"),
            FlowNode(id: "c", position: CGPoint(x: 200, y: 0), data: "C"),
        ]
        let edges = [
            FlowEdge(id: "ab", sourceNodeID: "a", targetNodeID: "b"),
            FlowEdge(id: "bc", sourceNodeID: "b", targetNodeID: "c"),
        ]
        let context = FlowLayoutContext(
            nodes: nodes,
            edges: edges,
            scope: .nodeIDs(["a", "b"])
        )

        #expect(context.scopedEdges.map(\.id) == ["ab"])
    }

    @Test("Store applies algorithm result")
    func storeAppliesAlgorithmResult() throws {
        var configuration = FlowConfiguration()
        configuration.snapToGrid = true
        configuration.gridSize = 10
        let store = FlowStore<String>(configuration: configuration)
        store.addNode(FlowNode(id: "a", position: .zero, data: "A"))
        store.addNode(FlowNode(id: "b", position: CGPoint(x: 100, y: 0), data: "B"))

        let result = try store.layout(
            using: OffsetLayoutAlgorithm(offset: CGSize(width: 13, height: 27))
        )

        #expect(result.positions.keys.sorted() == ["a", "b"])
        #expect(store.nodeLookup["a"]?.position == CGPoint(x: 10, y: 30))
        #expect(store.nodeLookup["b"]?.position == CGPoint(x: 110, y: 30))
    }

    @Test("AnyFlowLayoutAlgorithm erases concrete algorithm")
    func anyFlowLayoutAlgorithmErasesConcreteAlgorithm() throws {
        let store = FlowStore<String>()
        store.addNode(FlowNode(id: "a", position: .zero, data: "A"))
        let algorithm = AnyFlowLayoutAlgorithm(
            OffsetLayoutAlgorithm<String>(offset: CGSize(width: 40, height: 50))
        )

        try store.layout(using: algorithm)

        #expect(store.nodeLookup["a"]?.position == CGPoint(x: 40, y: 50))
    }
}

private struct OffsetLayoutAlgorithm<Data: Sendable & Hashable>: FlowLayoutAlgorithm {
    let offset: CGSize

    func layout(context: FlowLayoutContext<Data>) throws -> FlowLayoutResult {
        FlowLayoutResult(
            positions: Dictionary(
                uniqueKeysWithValues: context.scopedNodes.map { node in
                    (
                        node.id,
                        CGPoint(
                            x: node.position.x + offset.width,
                            y: node.position.y + offset.height
                        )
                    )
                }
            )
        )
    }
}
