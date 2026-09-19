import SwiftUI

/// Rendering only: every member remains in FlowStore for interaction and persistence.
struct NodeCompositePlan {
    /// Live content and every containing batch must stay on the individual path.
    /// Unrelated subtrees can remain composited while an editor is mounted.
    static func rootsExcludingLiveNodes<Data: Sendable & Hashable>(
        _ roots: Set<String>, nodes: [FlowNode<Data>], liveIDs: Set<String>
    ) -> Set<String> {
        guard !roots.isEmpty, !liveIDs.isEmpty else { return roots }
        let parents = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parentID) })
        var result = roots
        for liveID in liveIDs {
            var cursor: String? = liveID
            var visited = Set<String>()
            while let id = cursor, visited.insert(id).inserted {
                result.remove(id)
                cursor = parents[id] ?? nil
            }
        }
        return result
    }

    struct Batch: Identifiable {
        let id: String
        let members: [String]
        let bounds: CGRect
        let drawAtID: String
    }
    let batches: [Batch]
    let memberIDs: Set<String>
    let batchAtNodeID: [String: Batch]

    init<Data: Sendable & Hashable>(nodes: [FlowNode<Data>], backToFront: [Int], roots: Set<String>, inset: CGFloat) {
        guard !roots.isEmpty else {
            batches = []; memberIDs = []; batchAtNodeID = [:]; return
        }
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var owner: [String: String] = [:]
        for node in nodes {
            var cursor: String? = node.id
            var seen = Set<String>()
            var root: String?
            while let id = cursor, seen.insert(id).inserted {
                if roots.contains(id) { root = id }
                cursor = lookup[id]?.parentID
            }
            if let root { owner[node.id] = root }
        }
        let ordered = backToFront.map { nodes[$0] }
        var members: [String: [FlowNode<Data>]] = [:]
        var lastIndex: [String: Int] = [:]
        for (index, node) in ordered.enumerated() {
            if let root = owner[node.id] {
                members[root, default: []].append(node)
                lastIndex[root] = index
            }
        }
        var result: [Batch] = []
        // A batch is drawn at its last member. Moving earlier members across an
        // overlapping outsider would change painter order, so retain separate
        // symbols in that case. Non-overlapping interleaving is safe to batch.
        for root in roots.sorted() {
            guard let group = members[root], group.count > 1, let end = lastIndex[root] else { continue }
            var crossedBounds = CGRect.null
            var safe = true
            for node in ordered[...end] {
                let frame = node.frame.insetBy(dx: -inset, dy: -inset)
                if owner[node.id] == root {
                    crossedBounds = crossedBounds.union(frame)
                } else if !crossedBounds.isNull && crossedBounds.intersects(frame) {
                    safe = false; break
                }
            }
            guard safe, !crossedBounds.isNull, !crossedBounds.isInfinite,
                  crossedBounds.width > 0, crossedBounds.height > 0 else { continue }
            result.append(Batch(id: root, members: group.map(\.id), bounds: crossedBounds, drawAtID: ordered[end].id))
        }
        batches = result
        memberIDs = Set(result.flatMap(\.members))
        batchAtNodeID = Dictionary(uniqueKeysWithValues: result.map { ($0.drawAtID, $0) })
    }
}

struct CompositeNodeSymbolID: Hashable {
    let rootID: String
}

/// Cache only membership and geometry. Node content is always read from the
/// current store, so theme, selection and authored edits cannot leave stale pixels.
struct NodeCompositePlanCache {
    struct Input: Equatable {
        let id: String
        let parentID: String?
        let frame: CGRect
        let zIndex: Int
    }
    var inputs: [Input] = []
    var roots: Set<String> = []
    var plan: NodeCompositePlan?
}
