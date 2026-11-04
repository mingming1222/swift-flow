import CoreGraphics

/// Conservative visual coverage in canvas coordinates. Unknown coverage is
/// always retained; callers must not infer it from a layout frame alone.
public enum FlowVisualBounds: Sendable {
    case bounded(CGRect)
    case unknown
}

struct ViewportCullingConfiguration<Data: Sendable & Hashable> {
    let preloadMargin: CGFloat
    let retainedNodeIDs: Set<String>
    let visualBounds: (FlowNode<Data>) -> FlowVisualBounds
}

struct FlowViewportRenderPlan {
    enum Unit {
        case node(Int)
        case batch(NodeCompositePlan.Batch)
    }
    let preparedNodeIndices: [Int]
    let preparedBatches: [NodeCompositePlan.Batch]
    let drawUnits: [Unit]
    let unknownUnitCount: Int

    init<Data: Sendable & Hashable>(nodes: [FlowNode<Data>], backToFront: [Int],
         composite: NodeCompositePlan, viewport: Viewport, canvasSize: CGSize,
         preloadMargin: CGFloat, retainedIDs: Set<String>,
         visualBounds: (FlowNode<Data>) -> FlowVisualBounds) {
        let valid = canvasSize.width.isFinite && canvasSize.height.isFinite && canvasSize.width > 0 && canvasSize.height > 0
            && viewport.zoom.isFinite && viewport.zoom >= 0.01 && viewport.offset.x.isFinite && viewport.offset.y.isFinite
            && preloadMargin.isFinite && preloadMargin >= 0
        func canvasRect(_ margin: CGFloat) -> CGRect? {
            guard valid else { return nil }
            let a = viewport.screenToCanvas(.init(x: -margin, y: -margin))
            let b = viewport.screenToCanvas(.init(x: canvasSize.width + margin, y: canvasSize.height + margin))
            let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized
            return rect.isNull || rect.isInfinite || !rect.origin.x.isFinite || !rect.origin.y.isFinite
                || !rect.width.isFinite || !rect.height.isFinite ? nil : rect
        }
        let preparedRect = canvasRect(preloadMargin), visibleRect = canvasRect(0)
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let inset = FlowHandle.diameter / 2
        func validRect(_ rect: CGRect) -> Bool {
            !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
                && rect.width.isFinite && rect.height.isFinite
        }
        func overlaps(_ bounds: CGRect?, _ viewport: CGRect?) -> Bool {
            guard let bounds, let viewport else { return true }
            return bounds.minX <= viewport.maxX && bounds.maxX >= viewport.minX
                && bounds.minY <= viewport.maxY && bounds.maxY >= viewport.minY
        }
        func bounds(_ members: [FlowNode<Data>]) -> CGRect? {
            var result = CGRect.null
            for node in members {
                guard case let .bounded(rect) = visualBounds(node), validRect(rect), validRect(node.frame) else { return nil }
                result = result.union(rect.standardized).union(node.frame.insetBy(dx: -inset, dy: -inset))
            }
            return result.isNull ? nil : result
        }
        var preparedNodes = [Int](), batches = [NodeCompositePlan.Batch](), draw = [Unit]()
        var unknownCount = 0
        for index in backToFront {
            let node = nodes[index]
            if let batch = composite.batchAtNodeID[node.id] {
                let members = batch.members.compactMap { lookup[$0] }
                let coverage = members.count == batch.members.count ? bounds(members) : nil
                if coverage == nil { unknownCount += 1 }
                let retained = batch.members.contains { retainedIDs.contains($0) }
                let prepare = retained || overlaps(coverage, preparedRect)
                let visible = overlaps(coverage, visibleRect)
                if prepare { batches.append(batch) }
                if visible { draw.append(.batch(batch)) }
            }
            guard !composite.memberIDs.contains(node.id) else { continue }
            let coverage = bounds([node])
            if coverage == nil { unknownCount += 1 }
            let prepare = retainedIDs.contains(node.id) || overlaps(coverage, preparedRect)
            let visible = overlaps(coverage, visibleRect)
            if prepare { preparedNodes.append(index) }
            if visible { draw.append(.node(index)) }
        }
        self.preparedNodeIndices = preparedNodes
        self.preparedBatches = batches
        self.drawUnits = draw
        self.unknownUnitCount = unknownCount
    }
}
