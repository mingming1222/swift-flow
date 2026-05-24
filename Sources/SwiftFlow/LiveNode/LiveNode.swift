import Foundation
import SwiftUI

// MARK: - LiveNode

/// Declares a node whose body is rendered as a live SwiftUI view while
/// interactive, and as a rasterized snapshot while not interactive.
///
/// `LiveNode` must be used inside a `FlowCanvas` `nodeContent` closure.
/// The canvas injects the surrounding node's identity, size, and snapshot
/// through the environment, so the call site stays small:
///
/// ```swift
/// LiveNode(node: node) {
///     MyChartView()
/// }
/// ```
///
/// For native views (`WKWebView`, `MKMapView`, `AVPlayerView`) the developer
/// owns the underlying instance through `@State` and the wrapping
/// representable participates in the snapshot pipeline by reading
/// `\.liveNodePosterContext` from the environment:
///
/// ```swift
/// @State private var webView = WKWebView()
///
/// LiveNode(node: node, mount: .persistent) {
///     WebRepresentable(webView: webView, url: url)
/// }
/// ```
///
/// Inside `WebRepresentable.makeUIView` / `makeNSView` the developer reads
/// `\.liveNodePosterContext` and either registers a snapshot provider
/// (called during interaction end) or pushes a snapshot directly when an
/// internal event lands (navigation finish, tile render). See
/// ``LiveNodePosterContext`` for details.
public struct LiveNode<Content: View, Placeholder: View>: View {

    private let explicitNode: LiveNodeDescriptor?
    private let configuration: LiveNodeConfiguration
    private let content: (LiveNodeContentContext) -> Content
    private let placeholder: () -> Placeholder

    @Environment(\.liveNodeEnvironment) private var liveNodeEnvironment

    public init<Data>(
        node: FlowNode<Data>,
        mount: LiveNodeMountPolicy = .onInteraction,
        poster: LiveNodePosterPolicy = .automatic,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Data: Sendable & Hashable {
        self.explicitNode = LiveNodeDescriptor(node: node)
        self.configuration = LiveNodeConfiguration(
            mountPolicy: mount,
            posterPolicy: poster
        )
        self.content = { _ in content() }
        self.placeholder = placeholder
    }

    public init<Data>(
        node: FlowNode<Data>,
        mount: LiveNodeMountPolicy = .onInteraction,
        poster: LiveNodePosterPolicy = .automatic,
        @ViewBuilder content: @escaping (LiveNodeContentContext) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Data: Sendable & Hashable {
        self.explicitNode = LiveNodeDescriptor(node: node)
        self.configuration = LiveNodeConfiguration(
            mountPolicy: mount,
            posterPolicy: poster
        )
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        if let resolved = resolvedEnvironment {
            LiveNodeCore(
                environment: resolved,
                configuration: configuration,
                content: content,
                placeholder: placeholder
            )
        } else {
            placeholder()
        }
    }

    /// Merge precedence:
    ///
    /// 1. `LiveNode(node:)` overrides id and size.
    /// 2. The Canvas-injected `liveNodeEnvironment` supplies the
    ///    snapshot — and id / size when no explicit node is provided.
    /// 3. Without either source, the placeholder is rendered.
    private var resolvedEnvironment: LiveNodeEnvironment? {
        if let explicitNode {
            return LiveNodeEnvironment(
                id: explicitNode.id,
                size: explicitNode.size,
                snapshot: liveNodeEnvironment?.snapshot
            )
        }
        return liveNodeEnvironment
    }
}

extension LiveNode where Placeholder == FlowDefaultPlaceholder {
    public init<Data>(
        node: FlowNode<Data>,
        mount: LiveNodeMountPolicy = .onInteraction,
        poster: LiveNodePosterPolicy = .automatic,
        @ViewBuilder content: @escaping () -> Content
    ) where Data: Sendable & Hashable {
        self.init(
            node: node,
            mount: mount,
            poster: poster,
            content: content,
            placeholder: { FlowDefaultPlaceholder() }
        )
    }

    public init<Data>(
        node: FlowNode<Data>,
        mount: LiveNodeMountPolicy = .onInteraction,
        poster: LiveNodePosterPolicy = .automatic,
        @ViewBuilder content: @escaping (LiveNodeContentContext) -> Content
    ) where Data: Sendable & Hashable {
        self.init(
            node: node,
            mount: mount,
            poster: poster,
            content: content,
            placeholder: { FlowDefaultPlaceholder() }
        )
    }
}

// MARK: - Snapshot Registry

/// Per-`LiveNode` slots for explicit native and live-view snapshot providers.
///
/// Reference type so registering / clearing the handler from within
/// `makeUIView` / `dismantleUIView` does not invalidate the surrounding
/// SwiftUI body.
@MainActor
final class LiveNodeSnapshotRegistry {
    private var nativeHandler: (@MainActor () async -> FlowNodeSnapshot?)?
    private var mountedViewHandler: (@MainActor () async -> FlowNodeSnapshot?)?
    private var mountedViewHandlerToken: UUID?

    func setNativeSnapshotProvider(_ handler: @escaping @MainActor () async -> FlowNodeSnapshot?) {
        nativeHandler = handler
    }

    func clearNativeSnapshotProvider() {
        nativeHandler = nil
    }

    func nativeSnapshotProvider() -> (@MainActor () async -> FlowNodeSnapshot?)? {
        nativeHandler
    }

    func setMountedViewSnapshotProvider(
        token: UUID,
        handler: @escaping @MainActor () async -> FlowNodeSnapshot?
    ) {
        mountedViewHandlerToken = token
        mountedViewHandler = handler
    }

    func clearMountedViewSnapshotProvider(token: UUID) {
        guard mountedViewHandlerToken == token else {
            return
        }
        mountedViewHandlerToken = nil
        mountedViewHandler = nil
    }

    func mountedViewSnapshotProvider() -> (@MainActor () async -> FlowNodeSnapshot?)? {
        mountedViewHandler
    }

    func preferredSnapshotProvider() -> (@MainActor () async -> FlowNodeSnapshot?)? {
        nativeHandler ?? mountedViewHandler
    }

    var hasMountedViewSnapshotProvider: Bool {
        mountedViewHandler != nil
    }
}

// MARK: - Core

private struct LiveNodeCore<Content: View, Placeholder: View>: View {

    let environment: LiveNodeEnvironment
    let configuration: LiveNodeConfiguration
    let content: (LiveNodeContentContext) -> Content
    let placeholder: () -> Placeholder

    @Environment(\.flowNodeRenderPhase) private var phase
    @Environment(\.isFlowNodeInteractive) private var isInteractive
    @Environment(\.displayScale) private var displayScale
    @Environment(\.self) private var swiftUIEnvironment
    @Environment(\.flowLiveNodeSnapshotWriter) private var snapshotWriter
    @Environment(\.liveNodeInteractionCoordinator) private var coordinator
    @Environment(\.defersLiveNodeSnapshotWrites) private var defersSnapshotWrites

    @State private var snapshotRegistry = LiveNodeSnapshotRegistry()
    @State private var hasAttemptedInitialSnapshot: Bool = false
    @State private var isSeedingInitialSnapshot: Bool = false
    @State private var snapshotProviderReadinessRevision: Int = 0
    private var contentContext: LiveNodeContentContext {
        LiveNodeContentContext(
            id: environment.id,
            size: environment.size,
            snapshot: environment.snapshot,
            isInteractive: isInteractive
        )
    }

    var body: some View {
        phaseBody
            .frame(width: environment.size.width, height: environment.size.height)
            .preference(key: LiveNodePresenceKey.self, value: [environment.id])
            .preference(
                key: LiveNodeMountPolicyKey.self,
                value: [environment.id: configuration.mountPolicy]
            )
            .environment(\.liveNodePosterContext, makePosterContext())
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch phase {
        case .rasterize:
            RasterizedNodeBody(
                snapshot: environment.snapshot,
                placeholder: placeholder
            )

        case .live:
            LiveNodeLiveBody(
                nodeID: environment.id,
                snapshot: environment.snapshot,
                mountPolicy: configuration.mountPolicy,
                size: environment.size,
                scale: snapshotScale,
                snapshotRegistry: snapshotRegistry,
                swiftUIEnvironment: swiftUIEnvironment,
                snapshotProviderReady: {
                    snapshotProviderReadinessRevision += 1
                },
                content: { content(contentContext) }
            )
            .task(id: environment.id) {
                registerInteractionEndSnapshotProvider()
            }
            .task(id: initialSnapshotSeedTrigger) {
                await seedInitialSnapshotIfNeeded()
            }
            .onDisappear {
                unregisterInteractionEndSnapshotProvider()
            }
        }
    }

    private var initialSnapshotSeedTrigger: InitialSnapshotSeedTrigger {
        InitialSnapshotSeedTrigger(
            nodeID: environment.id,
            isSnapshotMissing: environment.snapshot == nil,
            readinessRevision: snapshotProviderReadinessRevision
        )
    }

    @MainActor
    private func registerInteractionEndSnapshotProvider() {
        coordinator?.registerPosterProvider(for: environment.id) {
            guard configuration.posterPolicy.interactionEndCapture == .automatic else {
                return
            }
            await refreshSnapshot(reason: "interactionEnd")
        }
    }

    @MainActor
    private func unregisterInteractionEndSnapshotProvider() {
        coordinator?.unregisterPosterProvider(for: environment.id)
    }

    @MainActor
    private func seedInitialSnapshotIfNeeded() async {
        guard configuration.posterPolicy.initialCapture == .automatic else { return }
        guard environment.snapshot == nil else { return }
        guard !hasAttemptedInitialSnapshot else { return }
        guard !isSeedingInitialSnapshot else { return }
        guard !defersSnapshotWrites else { return }
        guard snapshotRegistry.hasMountedViewSnapshotProvider else { return }
        guard let snapshotWriter else { return }

        tracePoster("initialCapture start")
        isSeedingInitialSnapshot = true
        defer {
            isSeedingInitialSnapshot = false
        }

        guard await Self.waitForStablePosterFrame() else {
            return
        }
        guard !Task.isCancelled else {
            return
        }

        hasAttemptedInitialSnapshot = true
        guard let snapshot = await produceSnapshot() else {
            tracePoster("initialCapture noSnapshot")
            return
        }
        guard !Task.isCancelled else {
            return
        }
        snapshotWriter(environment.id, snapshot)
        tracePoster("initialCapture wrote")
    }

    @MainActor
    @discardableResult
    private func refreshSnapshot(reason: String) async -> Bool {
        guard let snapshotWriter else { return false }
        guard !Task.isCancelled else {
            return false
        }
        tracePoster("\(reason) start")
        guard await Self.waitForStablePosterFrame() else {
            tracePoster("\(reason) cancelledBeforeStableFrame")
            return false
        }
        guard let snapshot = await produceSnapshot() else {
            tracePoster("\(reason) noSnapshot")
            return false
        }
        guard !Task.isCancelled else {
            return false
        }
        snapshotWriter(environment.id, snapshot)
        tracePoster("\(reason) wrote")
        return true
    }

    @MainActor
    private func produceSnapshot() async -> FlowNodeSnapshot? {
        guard let handler = snapshotRegistry.preferredSnapshotProvider() else {
            return nil
        }
        return await handler()
    }

    private var snapshotScale: CGFloat {
        min(max(displayScale * 2, 2), 4)
    }

    @MainActor
    private func makePosterContext() -> LiveNodePosterContext? {
        guard let snapshotWriter else { return nil }
        let nodeID = environment.id
        let registry = snapshotRegistry
        let allowsImmediateSnapshotWrites = !defersSnapshotWrites
        return LiveNodePosterContext(
            nodeID: nodeID,
            write: { snapshot in
                snapshotWriter(nodeID, snapshot)
            },
            registerPosterProvider: { handler in
                registry.setNativeSnapshotProvider(handler)
            },
            unregisterPosterProvider: {
                registry.clearNativeSnapshotProvider()
            },
            allowsImmediateSnapshotWrites: {
                allowsImmediateSnapshotWrites
            },
            requestPosterUpdate: {
                print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest start")
                guard let handler = registry.preferredSnapshotProvider() else {
                    print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest noProvider")
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                guard await Self.waitForStablePosterFrame() else {
                    print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest cancelledBeforeStableFrame")
                    return
                }
                guard let snapshot = await handler() else {
                    print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest noSnapshot")
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                snapshotWriter(nodeID, snapshot)
                print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest wrote")
            }
        )
    }

    private func tracePoster(_ event: String) {
        print(
            "[SwiftFlow][LiveNodePoster] node=\(environment.id) event=\(event) "
                + "snapshotMissing=\(environment.snapshot == nil) deferred=\(defersSnapshotWrites)"
        )
    }

    @MainActor
    private static func waitForStablePosterFrame() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return false
        }
        await Task.yield()
        return !Task.isCancelled
    }
}

private struct InitialSnapshotSeedTrigger: Hashable {
    let nodeID: String
    let isSnapshotMissing: Bool
    let readinessRevision: Int
}

// MARK: - Rasterized Body

private struct RasterizedNodeBody<Placeholder: View>: View {
    let snapshot: FlowNodeSnapshot?
    let placeholder: () -> Placeholder

    var body: some View {
        Group {
            if let snapshot {
                SnapshotImage(snapshot: snapshot)
            } else {
                placeholder()
            }
        }
    }
}

// MARK: - Live Body

private struct LiveNodeLiveBody<Content: View>: View {
    let nodeID: String
    let snapshot: FlowNodeSnapshot?
    let mountPolicy: LiveNodeMountPolicy
    let size: CGSize
    let scale: CGFloat
    let snapshotRegistry: LiveNodeSnapshotRegistry
    let swiftUIEnvironment: EnvironmentValues
    let snapshotProviderReady: () -> Void
    let content: () -> Content

    var body: some View {
        ZStack {
            if shouldDrawSnapshotBackdrop, let snapshot {
                SnapshotImage(snapshot: snapshot)
                    .allowsHitTesting(false)
            }

            content()
                .overlay(alignment: .topLeading) {
                    LiveNodeMountedViewSnapshotHost(
                        nodeID: nodeID,
                        size: size,
                        scale: scale,
                        registry: snapshotRegistry,
                        swiftUIEnvironment: swiftUIEnvironment,
                        snapshotProviderReady: snapshotProviderReady,
                        content: content
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }

    private var shouldDrawSnapshotBackdrop: Bool {
        switch mountPolicy {
        case .onInteraction:
            return true

        case .persistent:
            return false
        }
    }
}

// MARK: - Snapshot Image

private struct SnapshotImage: View {
    let snapshot: FlowNodeSnapshot

    var body: some View {
        Image(snapshot.cgImage, scale: snapshot.scale, label: Text(verbatim: ""))
            .resizable()
            .interpolation(.high)
    }
}

// MARK: - Snapshot Writer Environment

private struct FlowLiveNodeSnapshotWriterKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String, FlowNodeSnapshot) -> Void)? = nil
}

extension EnvironmentValues {
    /// Closure injected by `FlowCanvas` that lets `LiveNode` deposit
    /// captured snapshots into the owning store without knowing the
    /// store's generic type.
    var flowLiveNodeSnapshotWriter: (@MainActor (String, FlowNodeSnapshot) -> Void)? {
        get { self[FlowLiveNodeSnapshotWriterKey.self] }
        set { self[FlowLiveNodeSnapshotWriterKey.self] = newValue }
    }
}
