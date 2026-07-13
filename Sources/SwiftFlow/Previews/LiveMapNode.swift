#if DEBUG && (os(iOS) || os(macOS))
import Foundation
import SwiftUI
import MapKit
import CoreLocation

// MARK: - State Store

/// Per-node region cache for ``LiveMapNode``.
///
/// `LiveMapNode` keeps the underlying `MKMapView` mounted with
/// ``LiveNodeMountPolicy/persistent`` so MapKit's native renderer keeps
/// its identity across interaction changes. This observable store keeps
/// the last-seen region per node ID as a fallback for actual view
/// teardown, such as Preview reloads or sample app window recreation.
@MainActor
@Observable
final class LiveMapNodeStateStore {

    var regions: [String: MKCoordinateRegion] = [:]
    var mapViewIDs: [String: String] = [:]
    var makeCounts: [String: Int] = [:]
    var dismantleCounts: [String: Int] = [:]

    init() {}

    func recordMake(nodeID: String, mapView: MKMapView) {
        mapViewIDs[nodeID] = Self.mapID(for: mapView)
        makeCounts[nodeID, default: 0] += 1
    }

    func recordDismantle(nodeID: String, mapView: MKMapView) {
        mapViewIDs[nodeID] = Self.mapID(for: mapView)
        dismantleCounts[nodeID, default: 0] += 1
    }

    func diagnostics(for nodeID: String) -> LiveMapNodeDiagnostics {
        LiveMapNodeDiagnostics(
            nodeID: nodeID,
            mapID: mapViewIDs[nodeID] ?? "none",
            makeCount: makeCounts[nodeID, default: 0],
            dismantleCount: dismantleCounts[nodeID, default: 0]
        )
    }

    private static func mapID(for mapView: MKMapView) -> String {
        guard let liveMapView = mapView as? LiveMapNodeMapView else {
            return "unknown"
        }
        return String(format: "%08X", ObjectIdentifier(liveMapView).hashValue)
    }
}

struct LiveMapNodeDiagnostics: Sendable, Hashable {
    let nodeID: String
    let mapID: String
    let makeCount: Int
    let dismantleCount: Int
}

// MARK: - Public View

/// Drop-in `LiveNode` wrapper around `MKMapView`.
///
/// Hides the bookkeeping required to make a native MapView cooperate
/// with the Poster pattern:
///
/// - Mount policy is ``LiveNodeMountPolicy/persistent``: MapKit's native
///   renderer stays mounted across interaction changes, while the Canvas
///   still draws the poster when the node is idle.
/// - `MKMapSnapshotter` reads the mounted map's current region and rendering
///   configuration without relying on Screen Recording permission.
/// - Region persistence is read/write through the user-supplied
///   ``LiveMapNodeStateStore`` so pan/zoom survives real teardown.
/// - Tile pipeline kick: window-attach callback + hover-driven non-zero
///   bounds polling so the map renders without requiring a drag first.
struct LiveMapNode<Data>: View where Data: Sendable & Hashable {

    private let node: FlowNode<Data>
    private let initialCoordinate: CLLocationCoordinate2D
    private let stateStore: LiveMapNodeStateStore
    private let cornerRadius: CGFloat

    init(
        node: FlowNode<Data>,
        initialCoordinate: CLLocationCoordinate2D,
        stateStore: LiveMapNodeStateStore,
        cornerRadius: CGFloat = 0
    ) {
        self.node = node
        self.initialCoordinate = initialCoordinate
        self.stateStore = stateStore
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        LiveNode(node: node, mount: .persistent) {
            LiveMapRepresentable(
                nodeID: node.id,
                initialCoordinate: initialCoordinate,
                cornerRadius: cornerRadius,
                stateStore: stateStore
            )
        } placeholder: {
            Color.clear
        }
    }
}

// MARK: - MKMapView subclass

/// `MKMapView` subclass that fires a hook every time the view is attached
/// to a window. Polling for non-zero bounds is brittle (the polling task
/// can race with platform layout and exhaust before the view is in the
/// hierarchy); the window-attach callback is the deterministic signal
/// that AppKit/UIKit has placed the view and is about to lay it out.
final class LiveMapNodeMapView: MKMapView {

    var onWindowAttach: (@MainActor (LiveMapNodeMapView) -> Void)?

    #if os(macOS)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }
        let attach = onWindowAttach
        Task { @MainActor in
            attach?(self)
        }
    }
    #else
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            return
        }
        let attach = onWindowAttach
        Task { @MainActor in
            attach?(self)
        }
    }
    #endif
}

// MARK: - Coordinator

@MainActor
final class LiveMapNodeCoordinator: NSObject, MKMapViewDelegate {

    let nodeID: String
    let stateStore: LiveMapNodeStateStore
    private let initialRegion: MKCoordinateRegion

    /// Only flipped to `true` after a real-size `setRegion` has actually
    /// landed. Flipping it earlier would consume the hover edge on a
    /// still-zero-bounds view and leave MapKit's tile pipeline dormant
    /// forever: `updateInteractionState` would never see another false-to-true
    /// hover transition.
    private var wasInteractive = false

    private var interactionKickTask: Task<Void, Never>?

    private var allowsRegionPersistence = false

    private var posterContext: LiveNodePosterContext?

    init(
        nodeID: String,
        initialRegion: MKCoordinateRegion,
        stateStore: LiveMapNodeStateStore
    ) {
        self.nodeID = nodeID
        self.initialRegion = initialRegion
        self.stateStore = stateStore
    }

    func updateInteractionState(_ isHovered: Bool, mapView: MKMapView) {
        if !isHovered {
            wasInteractive = false
            interactionKickTask?.cancel()
            interactionKickTask = nil
            return
        }

        guard !wasInteractive else { return }
        guard interactionKickTask == nil else { return }
        scheduleInteractionKick(for: mapView)
    }

    /// Forces the map's tile pipeline to wake. Driven by either the
    /// window-attach callback on `LiveMapNodeMapView` or by
    /// `updateInteractionState` for hover updates that race ahead of the
    /// window attach. Idempotent via `wasInteractive`.
    func kickIfReady(_ mapView: MKMapView) {
        guard !wasInteractive else { return }
        guard mapView.window != nil else { return }
        if interactionKickTask == nil {
            scheduleInteractionKick(for: mapView)
        }
    }

    func tearDown() {
        posterContext?.unregisterPosterProvider()
        posterContext = nil
        interactionKickTask?.cancel()
        interactionKickTask = nil
        wasInteractive = false
    }

    func bindPosterProvider(
        mapView: MKMapView,
        posterContext: LiveNodePosterContext?,
        snapshotScale: CGFloat
    ) {
        self.posterContext?.unregisterPosterProvider()
        self.posterContext = posterContext
        guard let posterContext else { return }
        let nodeID = posterContext.nodeID
        posterContext.registerPosterProvider { [weak mapView] in
            guard let mapView else { return nil }
            return await Self.snapshot(
                mapView: mapView,
                nodeID: nodeID,
                scale: snapshotScale
            )
        }
    }

    private func scheduleInteractionKick(for mapView: MKMapView) {
        let regionSource = stateStore.regions[nodeID].map { ("cached", $0) } ?? ("initial", initialRegion)
        let region = regionSource.1

        interactionKickTask = Task { @MainActor [weak self, weak mapView] in
            for _ in 0..<60 {
                if Task.isCancelled { return }
                guard let view = mapView else { return }

                if view.bounds.width > 1, view.bounds.height > 1 {
                    self?.allowsRegionPersistence = true
                    Self.applyRegion(region, on: view)

                    do {
                        try await Task.sleep(nanoseconds: 16_000_000)
                    } catch {
                        return
                    }
                    if Task.isCancelled { return }

                    guard let view = mapView else { return }
                    Self.applyRegion(region, on: view)

                    self?.wasInteractive = true
                    self?.interactionKickTask = nil
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch {
                    return
                }
            }

            self?.interactionKickTask = nil
        }
    }

    func persistRegionIfUsable(from mapView: MKMapView, reason: String) {
        guard allowsRegionPersistence else {
            return
        }
        guard mapView.window != nil, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }
        let region = mapView.region
        stateStore.regions[nodeID] = region
    }

    private static func applyRegion(_ region: MKCoordinateRegion, on mapView: MKMapView) {
        mapView.setRegion(region, animated: false)
    }

    private static func snapshot(
        mapView: MKMapView,
        nodeID: String,
        scale: CGFloat
    ) async -> FlowNodeSnapshot? {
        let bounds = mapView.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            traceSnapshotFailure(
                nodeID: nodeID,
                error: LiveNodeSnapshotCaptureError.invalidLogicalSize(bounds.size)
            )
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = mapView.region
        options.preferredConfiguration = mapView.preferredConfiguration
        options.size = bounds.size
#if os(iOS)
        options.traitCollection = mapView.traitCollection.modifyingTraits { traits in
            traits.displayScale = scale
        }
#elseif os(macOS)
        options.appearance = mapView.effectiveAppearance
#endif

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let flowSnapshot = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<FlowNodeSnapshot, Error>) in
                snapshotter.start { snapshot, error in
                    if let snapshot {
#if os(iOS)
                        guard let cgImage = snapshot.image.cgImage else {
                            continuation.resume(
                                throwing: LiveNodeSnapshotCaptureError.imageUnavailable
                            )
                            return
                        }
#elseif os(macOS)
                        var proposedRect = CGRect(
                            origin: .zero,
                            size: snapshot.image.size
                        )
                        guard let cgImage = snapshot.image.cgImage(
                            forProposedRect: &proposedRect,
                            context: nil,
                            hints: nil
                        ) else {
                            continuation.resume(
                                throwing: LiveNodeSnapshotCaptureError.imageUnavailable
                            )
                            return
                        }
#endif
                        continuation.resume(
                            returning: FlowNodeSnapshot(
                                cgImage: cgImage,
                                scale: scale
                            )
                        )
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(
                            throwing: LiveNodeSnapshotCaptureError.imageUnavailable
                        )
                    }
                }
            }
            guard !Task.isCancelled else { return nil }
            return flowSnapshot
        } catch {
            traceSnapshotFailure(nodeID: nodeID, error: error)
            return nil
        }
    }

    private static func traceSnapshotFailure(nodeID: String, error: Error) {
        let failure = LiveNodeSnapshotFailure(
            nodeID: nodeID,
            stage: .nativeViewCapture,
            underlyingError: error
        )
        print("[SwiftFlow][LiveNodePoster] event=captureFailed \(failure)")
    }

    nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        Task { @MainActor [weak self, weak mapView] in
            guard let self, let mapView else { return }
            self.persistRegionIfUsable(from: mapView, reason: "regionDidChange")
        }
    }

}

// MARK: - Representable

#if os(iOS)
struct LiveMapRepresentable: UIViewRepresentable {

    @Environment(\.isFlowNodeHovered) private var isHovered
    @Environment(\.liveNodePosterContext) private var posterContext
    @Environment(\.displayScale) private var displayScale
    @Environment(\.liveNodeSnapshotDisplayScale) private var snapshotDisplayScale

    let nodeID: String
    let initialCoordinate: CLLocationCoordinate2D
    let cornerRadius: CGFloat
    let stateStore: LiveMapNodeStateStore

    func makeCoordinator() -> LiveMapNodeCoordinator {
        LiveMapNodeCoordinator(
            nodeID: nodeID,
            initialRegion: defaultRegion,
            stateStore: stateStore
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let coordinator = context.coordinator

        let mapView = LiveMapNodeMapView()
        stateStore.recordMake(nodeID: nodeID, mapView: mapView)
        mapView.delegate = coordinator
        mapView.layer.cornerRadius = cornerRadius
        mapView.layer.masksToBounds = true
        mapView.setRegion(initialRegion, animated: false)

        mapView.onWindowAttach = { [weak coordinator] view in
            coordinator?.kickIfReady(view)
        }
        coordinator.bindPosterProvider(
            mapView: mapView,
            posterContext: posterContext,
            snapshotScale: max(snapshotDisplayScale ?? displayScale, 1)
        )

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.layer.cornerRadius = cornerRadius
        coordinator.bindPosterProvider(
            mapView: mapView,
            posterContext: posterContext,
            snapshotScale: max(snapshotDisplayScale ?? displayScale, 1)
        )
        coordinator.updateInteractionState(isHovered, mapView: mapView)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: LiveMapNodeCoordinator) {
        coordinator.stateStore.recordDismantle(nodeID: coordinator.nodeID, mapView: mapView)
        coordinator.persistRegionIfUsable(from: mapView, reason: "dismantle")
        coordinator.tearDown()
        (mapView as? LiveMapNodeMapView)?.onWindowAttach = nil
        mapView.delegate = nil
    }

    private var initialRegion: MKCoordinateRegion {
        stateStore.regions[nodeID] ?? defaultRegion
    }

    private var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: initialCoordinate,
            latitudinalMeters: 3000,
            longitudinalMeters: 3000
        )
    }
}
#elseif os(macOS)
struct LiveMapRepresentable: NSViewRepresentable {

    @Environment(\.isFlowNodeHovered) private var isHovered
    @Environment(\.liveNodePosterContext) private var posterContext
    @Environment(\.displayScale) private var displayScale
    @Environment(\.liveNodeSnapshotDisplayScale) private var snapshotDisplayScale

    let nodeID: String
    let initialCoordinate: CLLocationCoordinate2D
    let cornerRadius: CGFloat
    let stateStore: LiveMapNodeStateStore

    func makeCoordinator() -> LiveMapNodeCoordinator {
        LiveMapNodeCoordinator(
            nodeID: nodeID,
            initialRegion: defaultRegion,
            stateStore: stateStore
        )
    }

    func makeNSView(context: Context) -> MKMapView {
        let coordinator = context.coordinator

        let mapView = LiveMapNodeMapView()
        stateStore.recordMake(nodeID: nodeID, mapView: mapView)
        mapView.delegate = coordinator
        mapView.wantsLayer = true
        mapView.layer?.cornerRadius = cornerRadius
        mapView.layer?.masksToBounds = true
        mapView.setRegion(initialRegion, animated: false)

        mapView.onWindowAttach = { [weak coordinator] view in
            coordinator?.kickIfReady(view)
        }
        coordinator.bindPosterProvider(
            mapView: mapView,
            posterContext: posterContext,
            snapshotScale: max(snapshotDisplayScale ?? displayScale, 1)
        )

        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.layer?.cornerRadius = cornerRadius
        coordinator.bindPosterProvider(
            mapView: mapView,
            posterContext: posterContext,
            snapshotScale: max(snapshotDisplayScale ?? displayScale, 1)
        )
        coordinator.updateInteractionState(isHovered, mapView: mapView)
    }

    static func dismantleNSView(_ mapView: MKMapView, coordinator: LiveMapNodeCoordinator) {
        coordinator.stateStore.recordDismantle(nodeID: coordinator.nodeID, mapView: mapView)
        coordinator.persistRegionIfUsable(from: mapView, reason: "dismantle")
        coordinator.tearDown()
        (mapView as? LiveMapNodeMapView)?.onWindowAttach = nil
        mapView.delegate = nil
    }

    private var initialRegion: MKCoordinateRegion {
        stateStore.regions[nodeID] ?? defaultRegion
    }

    private var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: initialCoordinate,
            latitudinalMeters: 3000,
            longitudinalMeters: 3000
        )
    }
}
#endif

#endif
