import Testing
import SwiftUI
@testable import SwiftFlow

@Suite("Composite node rendering") @MainActor
struct NodeCompositePlanTests {
    private func table() -> FlowStore<String> {
        var nodes = [FlowNode(id: "table", position: .zero, size: CGSize(width: 480, height: 180), data: "Table", zIndex: -2)]
        for i in 0..<20 {
            let point = CGPoint(x: (i % 4) * 120, y: (i / 4) * 36)
            nodes.append(FlowNode(id: "cell\(i)", position: point, size: CGSize(width: 120, height: 36), data: "Cell", parentID: "table", zIndex: -1))
            nodes.append(FlowNode(id: "text\(i)", position: point, size: CGSize(width: 112, height: 28), data: "Text", parentID: "cell\(i)"))
        }
        return FlowStore(nodes: nodes)
    }

    @Test func liveEditorExpandsOnlyContainingBatches() {
        let store = table()
        let roots: Set<String> = ["table", "cell0", "cell1"]
        let eligible = NodeCompositePlan.rootsExcludingLiveNodes(
            roots, nodes: store.nodes, liveIDs: ["text0"]
        )
        #expect(eligible == ["cell1"])
        // Separate this sibling spatially so the painter-order safeguard does
        // not intentionally reject its padded bounds against adjacent cells.
        store.updateNode("cell1") { $0.position = CGPoint(x: 2000, y: 0) }
        store.updateNode("text1") { $0.position = CGPoint(x: 2000, y: 0) }
        #expect(store.compositeNodePlan(roots: eligible).batches.map(\.id) == ["cell1"])
        #expect(NodeCompositePlan.rootsExcludingLiveNodes(
            roots, nodes: store.nodes, liveIDs: []
        ) == roots)
    }

    @Test func tableBecomesOneSymbolWithoutRemovingNodes() throws {
        let store = table()
        let plan = store.compositeNodePlan(roots: ["table", "cell0"])
        let batch = try #require(plan.batches.first)
        #expect(plan.batches.count == 1)
        #expect(batch.id == "table")
        #expect(batch.members.count == 41)
        #expect(plan.memberIDs.count == 41)
        #expect(store.nodes.count == 41)
        #expect(store.nodeLookup["text0"]?.parentID == "cell0")
        #expect(batch.bounds == CGRect(x: -FlowHandle.diameter / 2, y: -FlowHandle.diameter / 2,
                                     width: 480 + FlowHandle.diameter, height: 180 + FlowHandle.diameter))
        #expect(store.compositeNodePlan(roots: []).batches.isEmpty)
    }

    @Test func panZoomAndContentPreserveMembershipButGeometryChangesRefreshBounds() throws {
        let store = table()
        let original = try #require(store.compositeNodePlan(roots: ["table"]).batches.first)
        store.viewport = Viewport(offset: CGPoint(x: 900, y: 500), zoom: 2)
        store.updateNode("text0") { $0.data = "Changed" }
        let next = try #require(store.compositeNodePlan(roots: ["table"]).batches.first)
        #expect(next.members == original.members)
        #expect(next.bounds == original.bounds)
        #expect(store.nodeLookup["text0"]?.data == "Changed")
        store.updateNode("text0") { $0.position = CGPoint(x: 900, y: 800) }
        let moved = try #require(store.compositeNodePlan(roots: ["table"]).batches.first)
        #expect(moved.bounds.maxX > original.bounds.maxX)
        store.removeNode("cell0")
        #expect(!store.compositeNodePlan(roots: ["table"]).memberIDs.contains("text0"))
    }

    @Test func overlappingInterleavedOutsiderKeepsPainterOrder() {
        let store = table()
        store.addNode(FlowNode(id: "outside", position: CGPoint(x: 15, y: 15), data: "Outside", zIndex: -1))
        #expect(store.compositeNodePlan(roots: ["table"]).batches.isEmpty)
        store.updateNode("outside") { $0.position = CGPoint(x: 2000, y: 2000) }
        #expect(store.compositeNodePlan(roots: ["table"]).batches.count == 1)
    }

    @Test func severalDisjointGroupsAndReparenting() throws {
        let store = table()
        store.addNode(FlowNode(id: "other", position: CGPoint(x: 1500, y: 0), data: "Group", acceptsChildren: true, zIndex: -2))
        store.addNode(FlowNode(id: "child", position: CGPoint(x: 1500, y: 0), data: "Child", parentID: "other"))
        #expect(store.compositeNodePlan(roots: ["table", "other"]).batches.count == 2)
        store.setParent(of: "text0", to: nil)
        #expect(!store.compositeNodePlan(roots: ["table"]).memberIDs.contains("text0"))
        let document = store.export()
        store.load(document)
        #expect(store.nodeLookup["text0"]?.parentID == nil)
    }
    @Test func atomicGroupsStayOneSymbolAcrossInterleavingAndRigidMovement() throws {
        let store = table()
        store.addNode(FlowNode(id: "outside", position: CGPoint(x: 15, y: 15), data: "Outside", zIndex: -1))
        let before = try #require(store.compositeNodePlan(roots: ["table", "cell0"], atomic: true).batches.first)
        let ids = store.nodes.map(\.id)
        var deliveries = [[NodeChange<String>]]()
        store.onNodesChange = { deliveries.append($0) }
        store.configuration.snapToGrid = false
        store.beginNodeDrag("table")
        store.updateNodeDrag(translation: CGSize(width: 150, height: 70))
        #expect(deliveries.count == 1)
        #expect(deliveries[0].count == 41)
        let moved = try #require(store.compositeNodePlan(roots: ["table", "cell0"], atomic: true).batches.first)
        #expect(moved.members == before.members)
        #expect(moved.bounds == before.bounds.offsetBy(dx: 150, dy: 70))
        #expect(store.nodes.map(\.id) == ids)
        #expect(store.nodeLookup["outside"]?.position == CGPoint(x: 15, y: 15))
        store.updateNodeDrag(translation: CGSize(width: 150, height: 70))
        #expect(deliveries.count == 1, "Repeated pointer samples must not publish unchanged geometry")
    }

    @Test func symbolPixelsInvalidateForContentAndRelativeGeometryButNotTranslation() throws {
        let store = table()
        let batch = try #require(store.compositeNodePlan(roots: ["table"], atomic: true).batches.first)
        func symbol(_ nodes: [FlowNode<String>], _ bounds: CGRect, version: UInt64 = 1) -> CompositeNodeContent<String, Text> {
            CompositeNodeContent(nodes: nodes, contexts: [], bounds: bounds,
                contentVersion: version, hoveredID: nil, focusedTarget: nil,
                content: { Text($0.data) })
        }
        let original = symbol(store.nodes, batch.bounds)
        let translated = store.nodes.map { node in
            var result = node
            result.position.x += 120
            result.position.y -= 60
            return result
        }
        #expect(original == symbol(translated, batch.bounds.offsetBy(dx: 120, dy: -60)))
        var edited = translated
        edited[1].data = "New cell content"
        #expect(original != symbol(edited, batch.bounds.offsetBy(dx: 120, dy: -60)))
        edited = translated
        edited[1].position.x += 1
        #expect(original != symbol(edited, batch.bounds.offsetBy(dx: 120, dy: -60)))
        #expect(original != symbol(store.nodes, batch.bounds, version: 2))
    }

    @Test func atomicHitTestingUsesTheSameBoundaryAsPainterOrderAndExpandsOnEntry() {
        let nodes = [
            FlowNode(id: "group", position: .zero, size: CGSize(width: 200, height: 100), data: "Group", zIndex: -2),
            FlowNode(id: "first", position: .zero, size: CGSize(width: 80, height: 80), data: "First", parentID: "group", zIndex: -1),
            FlowNode(id: "outside", position: .zero, size: CGSize(width: 80, height: 80), data: "Outside", zIndex: 0),
            FlowNode(id: "last", position: CGPoint(x: 100, y: 0), size: CGSize(width: 80, height: 80), data: "Last", parentID: "group", zIndex: 1)
        ]
        let store = FlowStore(nodes: nodes)
        #expect(store.hitTestNode(at: CGPoint(x: 20, y: 20)) == "outside")
        store.atomicCompositeRootIDs = ["group"]
        #expect(store.hitTestNode(at: CGPoint(x: 20, y: 20)) == "first")
        #expect(store.nodesInHitTestOrder.map(\.id) == ["last", "first", "group", "outside"])
        store.atomicCompositeRootIDs = []
        #expect(store.hitTestNode(at: CGPoint(x: 20, y: 20)) == "outside")
    }

}
