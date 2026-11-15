import Testing
import SwiftUI
@testable import SwiftFlow

@Suite("Composite node rendering") @MainActor
struct NodeCompositePlanTests {
    @Test func directCompositeNeverBuildsMemberViewsAndNilFallsBack() throws {
        let nodes = (0..<1000).map { FlowNode(id: "n\($0)", position: .zero, size: CGSize(width: 20, height: 20), data: "leaf") }
        for direct in [true, false] {
            var memberCalls = 0
            var builderCalls = 0
            let view = CompositeNodeContent(nodes: nodes, contexts: [],
                bounds: CGRect(x: 0, y: 0, width: 20, height: 20), contentVersion: 1,
                hoveredID: nil, focusedTarget: nil,
                directContent: { members, _ in
                    builderCalls += 1
                    #expect(members.count == 1000)
                    return direct ? AnyView(Color.red) : nil
                }, content: { _ in memberCalls += 1; return Color.blue })
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            #expect(renderer.cgImage != nil)
            #expect(builderCalls > 0)
            #expect(direct ? memberCalls == 0 : memberCalls >= 1000)
        }
    }

    @Test func viewportRejectsDistantGroupBeforeDirectOrMemberPreparation() throws {
        var nodes: [FlowNode<String>] = []
        for (id, x) in [("visible", CGFloat(20)), ("distant", CGFloat(100_000))] {
            nodes.append(.init(id: id, position: CGPoint(x: x, y: 20), size: CGSize(width: 50, height: 50), data: id))
            for index in 0..<1000 {
                nodes.append(.init(id: "\(id)-\(index)", position: CGPoint(x: x, y: 20),
                    size: CGSize(width: 20, height: 20), data: id, parentID: id))
            }
        }
        let store = FlowStore(nodes: nodes)
        store.atomicCompositeRootIDs = ["visible", "distant"]
        var preparedIDs: Set<String> = []
        var memberCalls = 0
        let composite = store.compositeNodePlan(roots: store.atomicCompositeRootIDs, atomic: true)
        let viewport = FlowViewportRenderPlan(nodes: nodes,
            backToFront: Array(store.nodeIndicesFrontToBack.reversed()), composite: composite,
            viewport: store.viewport, canvasSize: CGSize(width: 300, height: 200),
            preloadMargin: 100, retainedIDs: [], visualBounds: { .bounded($0.frame) })
        #expect(viewport.preparedNodeIndices.isEmpty)
        #expect(viewport.preparedBatches.map(\.id) == ["visible"])
        for batch in viewport.preparedBatches {
            let view = CompositeNodeContent(nodes: batch.members.compactMap { store.nodeLookup[$0] },
                contexts: [], bounds: batch.bounds, contentVersion: 1, hoveredID: nil, focusedTarget: nil,
                directContent: { members, _ in
                    preparedIDs.formUnion(members.map(\.data))
                    return AnyView(Color.red)
                }, content: { _ in memberCalls += 1; return Color.blue })
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            #expect(renderer.cgImage != nil)
        }
        #expect(preparedIDs == ["visible"], "prepared: \(preparedIDs)")
        #expect(memberCalls == 0)
        #expect(store.nodes.count == 2002)
    }

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

    @Test func scopedSymbolInteractionOnlyChangesAffectedBatches() {
        func value(_ id: String, hover: String?, focus: FlowFocusTarget?, scoped: Bool) -> CompositeNodeContent<String, Text> {
            let node = FlowNode(id: id, position: .zero, data: id)
            let interaction = CompositeInteractionIdentity.resolve(members: [id], hover: hover, focus: focus, scoped: scoped)
            return CompositeNodeContent(nodes: [node], contexts: [.init()], bounds: .init(x: 0, y: 0, width: 160, height: 70),
                contentVersion: 1, hoveredID: interaction.hover, focusedTarget: interaction.focus, content: { Text($0.data) })
        }
        for id in ["A", "B", "C"] {
            let before = value(id, hover: "A", focus: .node("A"), scoped: true)
            let after = value(id, hover: "B", focus: .node("B"), scoped: true)
            #expect((before == after) == (id == "C"))
            let legacyBefore = value(id, hover: "A", focus: .node("A"), scoped: false)
            let legacyAfter = value(id, hover: "B", focus: .node("B"), scoped: false)
            #expect(legacyBefore != legacyAfter)
        }
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

    @Test func enteredAncestorDoesNotMaskAClosedNestedGroup() {
        let store = FlowStore(nodes: [
            FlowNode(id: "outer", position: .zero, data: "Outer", zIndex: 10),
            FlowNode(id: "inner", position: .zero, data: "Inner", parentID: "outer"),
            FlowNode(id: "leaf", position: .zero, data: "Leaf", parentID: "inner")
        ])
        store.atomicCompositeRootIDs = ["inner"]
        #expect(store.hitTestNode(at: CGPoint(x: 20, y: 20)) == "leaf")
        #expect(store.nodesInHitTestOrder.last?.id == "outer")
    }

    @Test func aStandaloneClosedComponentUsesTheSameCachedSymbolPath() throws {
        let store = FlowStore(nodes: [FlowNode(id: "component", position: .zero, data: "AST content")])
        #expect(store.compositeNodePlan(roots: ["component"]).batches.isEmpty)
        let atomic = try #require(store.compositeNodePlan(roots: ["component"], atomic: true).batches.first)
        #expect(atomic.members == ["component"])
        #expect(atomic.drawAtID == "component")
        store.beginNodeDrag("component")
        store.configuration.snapToGrid = false
        store.updateNodeDrag(translation: CGSize(width: 90, height: 30))
        let moved = try #require(store.compositeNodePlan(roots: ["component"], atomic: true).batches.first)
        #expect(moved.bounds == atomic.bounds.offsetBy(dx: 90, dy: 30))
    }

}
