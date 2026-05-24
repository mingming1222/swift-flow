import SwiftUI

/// Per-`LiveNode` channel that descendant views — typically
/// `UIViewRepresentable` / `NSViewRepresentable` wrappers around native
/// views — use when they intentionally need custom poster timing or a
/// custom poster source without taking on `LiveNode`'s internal coordinator
/// wiring.
///
/// Read it from the environment:
///
/// ```swift
/// @Environment(\.liveNodePosterContext) private var snapshot
/// ```
///
/// Three things the context lets a descendant do:
///
/// - ``write(_:)`` — push a snapshot directly when immediate writes are
///   allowed. During active node interaction this becomes a no-op so poster
///   events do not update under the user's pointer.
/// - ``registerPosterProvider(_:)`` — install an async snapshot provider that
///   `LiveNode` invokes during the interaction-end pipeline (and via
///   ``requestPosterUpdate()``). The handler typically reads from the live
///   native view weakly and produces a `FlowNodeSnapshot`.
/// - ``requestPosterUpdate()`` — explicitly drive a snapshot request on
///   demand when immediate writes are allowed.
///
/// The context is `nil` when a `LiveNode` is rendered outside a
/// `FlowCanvas` (rasterize-only previews) — there is nowhere to deposit
/// snapshots in that case, so all four operations become no-ops.
public struct LiveNodePosterContext: Sendable {

    public let nodeID: String

    let _write: @MainActor @Sendable (FlowNodeSnapshot) -> Void
    let _registerPosterProvider: @MainActor @Sendable (
        @escaping @MainActor () async -> FlowNodeSnapshot?
    ) -> Void
    let _unregisterPosterProvider: @MainActor @Sendable () -> Void
    let _allowsImmediateSnapshotWrites: @MainActor @Sendable () -> Bool
    let _requestPosterUpdate: @MainActor @Sendable () async -> Void

    public init(
        nodeID: String,
        write: @escaping @MainActor @Sendable (FlowNodeSnapshot) -> Void,
        registerPosterProvider: @escaping @MainActor @Sendable (
            @escaping @MainActor () async -> FlowNodeSnapshot?
        ) -> Void,
        unregisterPosterProvider: @escaping @MainActor @Sendable () -> Void,
        allowsImmediateSnapshotWrites: @escaping @MainActor @Sendable () -> Bool = { true },
        requestPosterUpdate: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.nodeID = nodeID
        self._write = write
        self._registerPosterProvider = registerPosterProvider
        self._unregisterPosterProvider = unregisterPosterProvider
        self._allowsImmediateSnapshotWrites = allowsImmediateSnapshotWrites
        self._requestPosterUpdate = requestPosterUpdate
    }

    @MainActor
    public var allowsImmediateSnapshotWrites: Bool {
        _allowsImmediateSnapshotWrites()
    }

    @MainActor
    public func write(_ snapshot: FlowNodeSnapshot) {
        guard allowsImmediateSnapshotWrites else {
            return
        }
        _write(snapshot)
    }

    @MainActor
    public func registerPosterProvider(
        _ handler: @escaping @MainActor () async -> FlowNodeSnapshot?
    ) {
        _registerPosterProvider(handler)
    }

    @MainActor
    public func unregisterPosterProvider() {
        _unregisterPosterProvider()
    }

    @MainActor
    public func requestPosterUpdate() async {
        guard allowsImmediateSnapshotWrites else {
            print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=explicitRequest skipped=deferred")
            return
        }
        await _requestPosterUpdate()
    }
}

private struct LiveNodePosterContextKey: EnvironmentKey {
    static let defaultValue: LiveNodePosterContext? = nil
}

public extension EnvironmentValues {
    /// Poster channel published by the surrounding `LiveNode`. Descendant
    /// views read this value only when they intentionally provide custom
    /// poster timing or a custom poster source.
    var liveNodePosterContext: LiveNodePosterContext? {
        get { self[LiveNodePosterContextKey.self] }
        set { self[LiveNodePosterContextKey.self] = newValue }
    }
}
