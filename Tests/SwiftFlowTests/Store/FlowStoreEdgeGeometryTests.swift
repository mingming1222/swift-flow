import Testing
import SwiftUI
@testable import SwiftFlow

@Suite("Cached edge geometry")
@MainActor
struct FlowStoreEdgeGeometryTests {
    private func fixture() -> FlowStore<String> {
        FlowStore(nodes: [
            FlowNode(id: "a", position: .zero, size: CGSize(width: 100, height: 80), data: "A",
                     handles: [.init(id: "out", type: .source, position: .right)]),
            FlowNode(id: "b", position: CGPoint(x: 400, y: 160), size: CGSize(width: 100, height: 80), data: "B",
                     handles: [.init(id: "in", type: .target, position: .left)]),
            FlowNode(id: "other", position: CGPoint(x: 800, y: 0), data: "Other")
        ], edges: [FlowEdge(id: "e", sourceNodeID: "a", sourceHandleID: "out", targetNodeID: "b", targetHandleID: "in")])
    }

    @Test func viewportAndPresentationReuseGeometry() throws {
        let store = fixture()
        let original = try #require(store.edgeGeometry(for: store.edges[0]))
        let entry = try #require(store.edgeGeometryCache.entries["e"])
        for frame in 1...240 {
            store.viewport = Viewport(offset: CGPoint(x: frame, y: -frame), zoom: CGFloat(frame) / 120 + 0.5)
            let geometry = try #require(store.edgeGeometry(for: store.edges[0]))
            #expect(store.edgeGeometryCache.entries["e"] === entry)
            #expect(geometry.path == original.path)
            #expect(geometry.bounds == original.bounds)
        }
        store.updateEdge("e") { $0.label = "new label"; $0.isSelected = true }
        store.moveNode("other", to: CGPoint(x: 900, y: 100))
        _ = store.edgeGeometry(for: store.edges[0])
        #expect(store.edgeGeometryCache.entries["e"] === entry)
    }

    @Test func movementResizePortsAndRoutingInvalidate() throws {
        let store = fixture()
        _ = store.edgeGeometry(for: store.edges[0])
        var entry = try #require(store.edgeGeometryCache.entries["e"])
        let changes: [() -> Void] = [
            { store.moveNode("a", to: CGPoint(x: 30, y: 20)) },
            { store.updateNode("b") { $0.size = CGSize(width: 160, height: 120) } },
            { store.updateNode("a") { $0.handles = [.init(id: "out", type: .source, position: .bottom)] } },
            { store.updateEdge("e") { $0.pathType = .straight } },
            { store.updateEdge("e") { $0.targetHandleID = nil } },
            { store.updateEdge("e") { $0.targetNodeID = "other" } }
        ]
        for change in changes {
            change()
            let geometry = try #require(store.edgeGeometry(for: store.edges[0]))
            let next = try #require(store.edgeGeometryCache.entries["e"])
            #expect(next !== entry)
            // Compare with a fresh store to catch stale paths, labels and bounds.
            let fresh = FlowStore(nodes: store.nodes, edges: store.edges)
            let expected = try #require(fresh.edgeGeometry(for: fresh.edges[0]))
            #expect(geometry.path == expected.path)
            #expect(geometry.bounds == expected.bounds)
            #expect(geometry.labelPosition == expected.labelPosition)
            #expect(geometry.labelAngle == expected.labelAngle)
            #expect(store.edgeGeometryCache.entries.count == 1)
            entry = next
        }
    }

    @Test func missingPortsDeletionAndLoadClearEntries() throws {
        let store = fixture()
        _ = store.edgeGeometry(for: store.edges[0])
        store.updateNode("a") { $0.handles = [] }
        #expect(store.edgeGeometry(for: store.edges[0]) == nil)
        #expect(store.edgeGeometryCache.entries.isEmpty)
        store.updateEdge("e") { $0.sourceHandleID = nil }
        _ = store.edgeGeometry(for: store.edges[0])
        store.removeEdge("e")
        #expect(store.edgeGeometryCache.entries.isEmpty)
        let replacement = fixture()
        store.load(replacement.export())
        _ = store.edgeGeometry(for: store.edges[0])
        store.load(replacement.export())
        #expect(store.edgeGeometryCache.entries.isEmpty)
        _ = store.edgeGeometry(for: store.edges[0])
        store.removeNode("a")
        #expect(store.edgeGeometryCache.entries.isEmpty)
    }

    @Test func undoAndRedoResolveCurrentEndpoints() throws {
        let store = fixture()
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let before = try #require(store.edgeGeometry(for: store.edges[0]))
        undo.beginUndoGrouping()
        store.beginNodeDrag("a")
        store.updateNodeDrag(translation: CGSize(width: 60, height: 40))
        store.endNodeDrag()
        undo.endUndoGrouping()
        let moved = try #require(store.edgeGeometry(for: store.edges[0]))
        #expect(moved.path != before.path || moved.bounds != before.bounds)
        undo.undo()
        let restored = try #require(store.edgeGeometry(for: store.edges[0]))
        #expect(restored.path == before.path)
        #expect(restored.bounds == before.bounds)
        undo.redo()
        let redone = try #require(store.edgeGeometry(for: store.edges[0]))
        #expect(redone.path == moved.path)
        #expect(redone.bounds == moved.bounds)
    }
}
