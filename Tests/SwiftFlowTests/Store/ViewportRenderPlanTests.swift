import Testing
import SwiftUI
@testable import SwiftFlow

@Suite @MainActor struct ViewportRenderPlanTests {
    @Test func keepsFullBatchWhenOnlyChildIsVisible() throws {
        let nodes = [FlowNode(id: "group", position: .init(x: 1000, y: 1000), data: "group"),
                     FlowNode(id: "child", position: .init(x: 30, y: 30), data: "child", parentID: "group"),
                     FlowNode(id: "far", position: .init(x: 2000, y: 2000), data: "far")]
        let order = Array(nodes.indices)
        let composite = NodeCompositePlan(nodes: nodes, backToFront: order, roots: ["group"], inset: 5, atomic: true)
        let batch = try #require(composite.batches.first)
        let result = FlowViewportRenderPlan(nodes: nodes, backToFront: order, composite: composite,
            viewport: .init(), canvasSize: .init(width: 200, height: 200), preloadMargin: 100,
            retainedIDs: [], visualBounds: { .bounded($0.frame) })
        #expect(result.preparedBatches.count == 1)
        #expect(result.preparedBatches[0].members == batch.members)
        #expect(result.preparedBatches[0].bounds == batch.bounds)
        #expect(result.preparedBatches[0].drawAtID == batch.drawAtID)
        #expect(result.preparedNodeIndices.isEmpty)
        #expect(result.drawUnits.count == 1)
    }

    @Test func unknownAndExplicitRetentionStayPreparedAndInvalidViewportIsConservative() {
        let nodes = [FlowNode(id: "far", position: .init(x: 1000, y: 0), data: "far"),
                     FlowNode(id: "unknown", position: .init(x: 2000, y: 0), data: "unknown")]
        let order = Array(nodes.indices)
        let composite = NodeCompositePlan(nodes: nodes, backToFront: order, roots: [], inset: 5)
        func plan(size: CGSize) -> FlowViewportRenderPlan {
            .init(nodes: nodes, backToFront: order, composite: composite, viewport: .init(offset: .init(x: -20, y: 0), zoom: 2),
                canvasSize: size, preloadMargin: 100, retainedIDs: ["far"],
                visualBounds: { $0.id == "unknown" ? .unknown : .bounded($0.frame) })
        }
        let valid = plan(size: .init(width: 200, height: 200))
        #expect(valid.preparedNodeIndices == [0, 1])
        #expect(valid.unknownUnitCount == 1)
        #expect(valid.drawUnits.count == 1)
        #expect(plan(size: .zero).drawUnits.count == 2)
    }

    @Test func marginUsesScreenPointsAndOrderingIsUnchanged() {
        let nodes = [FlowNode(id: "visible", position: .init(x: 20, y: 20), data: "visible"),
                     FlowNode(id: "near", position: .init(x: 130, y: 20), data: "near"),
                     FlowNode(id: "far", position: .init(x: 260, y: 20), data: "far")]
        let order = Array(nodes.indices)
        let composite = NodeCompositePlan(nodes: nodes, backToFront: order, roots: [], inset: 5)
        let result = FlowViewportRenderPlan(nodes: nodes, backToFront: order, composite: composite,
            viewport: .init(offset: .init(x: -20, y: 0), zoom: 2), canvasSize: .init(width: 200, height: 200),
            preloadMargin: 100, retainedIDs: [], visualBounds: { .bounded($0.frame) })
        #expect(result.preparedNodeIndices == [0, 1])
        #expect(result.drawUnits.count == 1)
    }

    @Test func touchingViewportBoundaryIsVisibleAndInvalidBoundsAreUnknown() {
        let nodes = [FlowNode(id: "edge", position: .init(x: 205, y: 20), size: .init(width: 20, height: 20), data: "edge"),
                     FlowNode(id: "invalid", position: .init(x: 400, y: 0), data: "invalid")]
        let order = Array(nodes.indices)
        let composite = NodeCompositePlan(nodes: nodes, backToFront: order, roots: [], inset: 5)
        let result = FlowViewportRenderPlan(nodes: nodes, backToFront: order, composite: composite,
            viewport: .init(), canvasSize: .init(width: 200, height: 200), preloadMargin: 0,
            retainedIDs: [], visualBounds: { $0.id == "invalid" ? .bounded(.init(x: CGFloat.nan, y: 0, width: 1, height: 1)) : .bounded($0.frame) })
        #expect(result.preparedNodeIndices == [0, 1])
        #expect(result.unknownUnitCount == 1)
        #expect(result.drawUnits.count == 2)
    }

    @Test func moreDistantKnownNodesDoNotExpandPreparedSymbols() {
        func plan(_ count: Int) -> FlowViewportRenderPlan {
            let nodes = [FlowNode(id: "near", position: .init(x: 50, y: 50), data: "near")]
                + (0..<count).map { FlowNode(id: "far-\($0)", position: .init(x: 10_000 + $0 * 200, y: 10_000), data: "far") }
            let order = Array(nodes.indices)
            let composite = NodeCompositePlan(nodes: nodes, backToFront: order, roots: [], inset: 5)
            return .init(nodes: nodes, backToFront: order, composite: composite, viewport: .init(),
                canvasSize: .init(width: 400, height: 300), preloadMargin: 100,
                retainedIDs: [], visualBounds: { .bounded($0.frame) })
        }
        let small = plan(10), large = plan(1000)
        #expect(small.preparedNodeIndices.count == 1)
        #expect(large.preparedNodeIndices.count == 1)
        #expect(small.drawUnits.count == 1)
        #expect(large.drawUnits.count == 1)
        #expect(large.unknownUnitCount == 0)
    }
}
