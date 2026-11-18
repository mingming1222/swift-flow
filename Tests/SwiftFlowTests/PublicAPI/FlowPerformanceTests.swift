import Foundation
import SwiftUI
import Synchronization
import Testing
@testable import SwiftFlow
#if os(macOS)
import AppKit
#endif

private final class PerformanceSamples: Sendable {
    private let storage = Mutex<[FlowPerformance.Sample]>([])
    func append(_ sample: FlowPerformance.Sample) { storage.withLock { $0.append(sample) } }
    var samples: [FlowPerformance.Sample] { storage.withLock { $0 } }
    func count(_ name: String) -> Int {
        samples.filter { $0.kind == .counter && $0.name.description == name }.reduce(0) { $0 + $1.count }
    }
    func durations(_ name: String) -> [FlowPerformance.Sample] {
        samples.filter { $0.kind == .duration && $0.name.description == name }
    }
}

@Suite(.serialized) @MainActor
struct FlowPerformanceTests {
    @Test func viewportAndPlansEmitActualWork() {
        let output = PerformanceSamples()
        FlowPerformance.configure { output.append($0) }
        defer { FlowPerformance.configure(sink: nil) }
        let nodes = [
            FlowNode(id: "root", position: .init(x: 10, y: 10), data: "private-root"),
            FlowNode(id: "child", position: .init(x: 20, y: 20), data: "private-child", parentID: "root"),
            FlowNode(id: "far", position: .init(x: 5000, y: 5000), data: "private-far")
        ]
        let store = FlowStore(nodes: nodes)
        store.performanceScope = 41
        store.pan(by: .init(width: 10, height: 5))
        store.pan(by: .zero)
        store.configuration.panEnabled = false
        store.pan(by: .init(width: 9, height: 9))
        store.zoom(by: 2, anchor: .zero)
        store.zoom(by: 100, anchor: .zero)
        store.configuration.zoomEnabled = false
        store.zoom(by: 2, anchor: .zero)
        let composite = store.compositeNodePlan(roots: ["root"], atomic: true)
        _ = store.compositeNodePlan(roots: ["root"], atomic: true)
        let plan = FlowViewportRenderPlan(nodes: nodes, backToFront: Array(nodes.indices),
            composite: composite, viewport: .init(), canvasSize: .init(width: 400, height: 300),
            preloadMargin: 0, retainedIDs: [], visualBounds: { .bounded($0.frame) }, performanceScope: 41)
        #expect(output.durations("flow.viewport.pan.apply").count == 3)
        #expect(output.count("flow.viewport.pan.changed") == 1)
        #expect(output.count("flow.viewport.pan.disabled") == 1)
        #expect(output.durations("flow.viewport.zoom.apply").count == 3)
        #expect(output.count("flow.viewport.zoom.changed") == 2)
        #expect(output.count("flow.viewport.zoom.clamped") == 1)
        #expect(output.count("flow.viewport.zoom.disabled") == 1)
        #expect(output.count("flow.render.composite.cache_hit") == 1)
        #expect(output.count("flow.render.composite.cache_miss") == 1)
        #expect(output.count("flow.render.composite.members") == composite.memberIDs.count)
        #expect(output.count("flow.render.viewport.scanned") == 3)
        #expect(output.count("flow.render.viewport.prepared_batches") == plan.preparedBatches.count)
        #expect(output.count("flow.render.viewport.draw_units") == 1)
        #expect(output.durations("flow.render.viewport_plan").count == 1)
        #expect(output.samples.allSatisfy { $0.scope == 41 && !$0.name.description.contains("private") })
    }

    @Test func captureCompletionAndStaleWritesAreDifferentOutcomes() async throws {
        let output = PerformanceSamples()
        FlowPerformance.configure { output.append($0) }
        defer { FlowPerformance.configure(sink: nil) }
        let registry = LiveNodeSnapshotRegistry()
        let image = try TestCGImageFactory.make(width: 20, height: 10)
        let snapshot = FlowNodeSnapshot(cgImage: image, scale: 1)
        registry.setNativeSnapshotProvider { snapshot }
        let provider = try #require(registry.preferredSnapshotProvider(allowsMountedView: false))
        let result = try #require(await registry.capture(using: provider, performanceScope: 42))
        _ = await registry.capture(using: { nil }, performanceScope: 42)
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await registry.capture(using: provider, performanceScope: 42)
        }
        _ = await cancelled.value
        let store = FlowStore(nodes: [FlowNode(id: "node", position: .zero, data: "private")])
        store.performanceScope = 42
        let generation = store.currentSnapshotGeneration()
        store.setNodeSnapshot(result, for: "node", generation: generation)
        store.clearNodeSnapshot(for: "node")
        store.clearNodeSnapshot(for: "node")
        store.setNodeSnapshot(result, for: "node")
        store.updateNodeSize("node", size: .init(width: 200, height: 100))
        store.clearAllNodeSnapshots()
        store.setNodeSnapshot(result, for: "node", generation: generation)
        store.setNodeSnapshot(result, for: "missing")
        #expect(store.nodeSnapshots.isEmpty)
        #expect(output.count("flow.snapshot.capture.request") == 3)
        #expect(output.count("flow.snapshot.capture.completed") == 1)
        #expect(output.count("flow.snapshot.capture.failed") == 1)
        #expect(output.count("flow.snapshot.capture.cancelled") == 1)
        #expect(output.durations("flow.snapshot.capture.provider").count == 3)
        #expect(output.count("flow.snapshot.capture.pixels") == 200)
        #expect(output.count("flow.snapshot.write.accepted") == 2)
        #expect(output.count("flow.snapshot.write.stale") == 1)
        #expect(output.count("flow.snapshot.write.missing_node") == 1)
        #expect(output.count("flow.snapshot.invalidate.request") == 3)
        #expect(output.count("flow.snapshot.invalidate.removed") == 2)
        #expect(output.samples.allSatisfy { $0.scope == 42 })
    }

    @Test func disabledDoesNotEvaluateMetricsOrChangeResults() {
        FlowPerformance.configure(sink: nil)
        var evaluated = false
        func expensiveCount() -> Int { evaluated = true; return 3 }
        FlowPerformance.count("disabled", expensiveCount(), scope: 43)
        #expect(FlowPerformance.begin(scope: 43) == nil)
        #expect(!evaluated)
        let store = FlowStore<String>()
        store.pan(by: .init(width: 5, height: 7))
        #expect(store.viewport.offset == .init(x: 5, y: 7))
        let output = PerformanceSamples()
        FlowPerformance.configure { sample in
            output.append(sample)
            // Reconfiguration in a consumer callback must not deadlock.
            FlowPerformance.configure(sink: nil)
        }
        store.pan(by: .zero)
        let count = output.samples.count
        store.pan(by: .zero)
        #expect(output.samples.count == count)
        #expect(count > 0)
    }

    @Test func rasterizedCacheHitsAndMissesAreConsumerVisible() throws {
        let output = PerformanceSamples()
        FlowPerformance.configure { output.append($0) }
        defer { FlowPerformance.configure(sink: nil) }
        let node = FlowNode(id: "poster", position: .zero, size: .init(width: 20, height: 10), data: "private")
        let snapshot = FlowNodeSnapshot(cgImage: try TestCGImageFactory.make(width: 20, height: 10), scale: 1)
        for cached in [nil, snapshot] as [FlowNodeSnapshot?] {
            let view = LiveNode(node: node, content: { Color.red }, placeholder: { Color.gray })
                .environment(\.liveNodeEnvironment, LiveNodeEnvironment(id: node.id, size: node.size, snapshot: cached))
                .environment(\.flowPerformanceScope, 45)
            let renderer = ImageRenderer(content: view)
            #expect(renderer.cgImage != nil)
        }
        #expect(output.count("flow.snapshot.cache.hit") > 0)
        #expect(output.count("flow.snapshot.cache.miss") > 0)
        #expect(output.samples.allSatisfy { $0.scope == 45 })
    }

    #if os(macOS)
    @Test func realCanvasDrawAndMountedReadinessReachConsumer() async throws {
        let output = PerformanceSamples()
        FlowPerformance.configure { output.append($0) }
        defer { FlowPerformance.configure(sink: nil) }
        _ = NSApplication.shared
        let directBack = FlowNode(id: "back", position: .init(x: 20, y: 20), data: "node", zIndex: -1)
        let directFront = FlowNode(id: "front", position: .init(x: 25, y: 23), data: "node", zIndex: 1)
        let store = FlowStore(nodes: [
            directFront, directBack,
            FlowNode(id: "fallback", position: .zero, data: "node"),
            FlowNode(id: "candidate", position: .zero, data: "node"),
            FlowNode(id: "snapshot", position: .zero, data: "node"),
            FlowNode(id: "distant", position: .init(x: 100_000, y: 100_000), data: "node"),
        ], viewport: .init(offset: .init(x: 5, y: 10), zoom: 2))
        store.performanceScope = 44
        let image = try TestCGImageFactory.make(width: 20, height: 20)
        store.setNodeSnapshot(FlowNodeSnapshot(cgImage: image, scale: 1), for: "snapshot")
        let registry = LiveNodeSnapshotRegistry()
        var preparedIDs: Set<String> = []
        var symbolIDs: Set<String> = []
        var directDraws: [(id: String, transform: CGAffineTransform)] = []
        let content = FlowCanvas(store: store) { node, _ in
            symbolIDs.insert(node.id)
            return Color.red
        }
            .liveNodeCandidates(["candidate"])
            .directNodeDrawing { node in
                preparedIDs.insert(node.id)
                guard node.id != "fallback" else { return nil }
                return { context in
                    directDraws.append((node.id, context.transform))
                    context.fill(Path(CGRect(origin: .zero, size: node.size)), with: .color(.blue))
                    context.translateBy(x: 1_000, y: 1_000)
                }
            }
            .viewportCulling(preloadMargin: 0, visualBounds: { .bounded($0.frame) })
            .overlay {
                LiveNodeMountedViewSnapshotHost(nodeID: "surface", size: .init(width: 20, height: 20),
                    scale: 1, isSurfaceVisible: false, registry: registry, snapshotProviderReady: {})
                    .environment(\.flowPerformanceScope, 44)
            }
            .frame(width: 320, height: 240)
            .environment(\.displayScale, 1)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            if directDraws.count >= 2 && output.count("flow.snapshot.provider.layout_ready") > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!output.durations("flow.render.prepare").isEmpty)
        #expect(!output.durations("flow.render.draw_callback").isEmpty)
        #expect(output.count("flow.render.symbol.attempted") > 0)
        #expect(output.count("flow.render.symbol.resolved") > 0)
        #expect(output.count("flow.render.node.direct_drawn") >= 2)
        #expect(preparedIDs == ["back", "front", "fallback"])
        #expect(symbolIDs == ["fallback", "candidate", "snapshot"])
        let firstDraws = Array(directDraws.prefix(2))
        #expect(firstDraws.map(\.id) == ["back", "front"])
        #expect(firstDraws.map(\.transform) == [directBack, directFront].map { node in
            let origin = store.viewport.canvasToScreen(node.position)
            return CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: origin.x, ty: origin.y)
        })
        #expect(output.count("flow.snapshot.provider.layout_ready") == 1)
        #expect(output.samples.allSatisfy { $0.scope == 44 })
    }
    #endif
}
