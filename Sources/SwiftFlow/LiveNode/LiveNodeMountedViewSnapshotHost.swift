import CoreGraphics
import Foundation
import SwiftUI

@MainActor
struct LiveNodeMountedViewSnapshotHost: View {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let isSurfaceVisible: Bool
    let registry: LiveNodeSnapshotRegistry
    let snapshotProviderReady: () -> Void

    var body: some View {
        PlatformMountedViewSnapshotHost(
            nodeID: nodeID,
            size: size,
            scale: scale,
            isSurfaceVisible: isSurfaceVisible,
            registry: registry,
            snapshotProviderReady: snapshotProviderReady
        )
        .frame(width: size.width, height: size.height)
    }
}

#if os(macOS)
import AppKit

@MainActor
private struct PlatformMountedViewSnapshotHost: NSViewRepresentable {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let isSurfaceVisible: Bool
    let registry: LiveNodeSnapshotRegistry
    let snapshotProviderReady: () -> Void

    func makeNSView(context: Context) -> MountedViewSnapshotNSView {
        MountedViewSnapshotNSView(
            capturer: ScreenCaptureKitLiveNodeWindowCapturer()
        )
    }

    func updateNSView(_ nsView: MountedViewSnapshotNSView, context: Context) {
        nsView.update(
            nodeID: nodeID,
            size: size,
            scale: scale,
            isSurfaceVisible: isSurfaceVisible,
            registry: registry,
            snapshotProviderReady: snapshotProviderReady
        )
    }

    static func dismantleNSView(_ nsView: MountedViewSnapshotNSView, coordinator: ()) {
        nsView.unregisterSnapshotProvider()
    }
}

@MainActor
private final class MountedViewSnapshotNSView: NSView {
    private let token = UUID()
    private let capturer: any LiveNodeWindowCapturing
    private weak var registry: LiveNodeSnapshotRegistry?
    private var nodeID: String = ""
    private var snapshotSize: CGSize = .zero
    private var snapshotScale: CGFloat = 1
    private var isSurfaceVisible = false
    private var snapshotProviderReady: (() -> Void)?
    private var didNotifySnapshotProviderReady = false

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(capturer: any LiveNodeWindowCapturing) {
        self.capturer = capturer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func update(
        nodeID: String,
        size: CGSize,
        scale: CGFloat,
        isSurfaceVisible: Bool,
        registry: LiveNodeSnapshotRegistry,
        snapshotProviderReady: @escaping () -> Void
    ) {
        self.nodeID = nodeID
        snapshotSize = size
        snapshotScale = scale
        self.isSurfaceVisible = isSurfaceVisible
        self.snapshotProviderReady = snapshotProviderReady
        self.registry = registry
        registry.setMountedViewSnapshotProvider(token: token) { [weak self] in
            guard let self else { return nil }
            do {
                return try await self.snapshotMountedNode()
            } catch {
                self.traceFailure(error)
                return nil
            }
        }
        notifySnapshotProviderReadyIfPossible()
    }

    func unregisterSnapshotProvider() {
        registry?.clearMountedViewSnapshotProvider(token: token)
        registry = nil
        didNotifySnapshotProviderReady = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifySnapshotProviderReadyIfPossible()
    }

    override func layout() {
        super.layout()
        notifySnapshotProviderReadyIfPossible()
    }

    private func snapshotMountedNode() async throws -> FlowNodeSnapshot {
        guard isSurfaceVisible else {
            throw LiveNodeSnapshotCaptureError.surfaceNotVisible
        }
        guard let window else {
            throw LiveNodeSnapshotCaptureError.windowUnavailable
        }
        guard bounds.width > 1, bounds.height > 1 else {
            throw LiveNodeSnapshotCaptureError.invalidLogicalSize(bounds.size)
        }

        window.contentView?.layoutSubtreeIfNeeded()
        let windowRect = convert(bounds, to: nil)
        let nodeScreenRect = window.convertToScreen(windowRect)
        let windowScreenFrame = window.frame
        return try await LiveNodeMountedWindowSnapshotter(capturer: capturer).snapshot(
            windowID: CGWindowID(window.windowNumber),
            nodeScreenRect: nodeScreenRect,
            windowScreenFrame: windowScreenFrame,
            logicalSize: snapshotSize,
            scale: snapshotScale
        )
    }

    private func notifySnapshotProviderReadyIfPossible() {
        guard window != nil else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard !didNotifySnapshotProviderReady else { return }
        didNotifySnapshotProviderReady = true
        Task { @MainActor [weak self] in
            self?.snapshotProviderReady?()
        }
    }

    private func traceFailure(_ error: Error) {
        let failure = LiveNodeSnapshotFailure(
            nodeID: nodeID,
            stage: .mountedWindowCapture,
            underlyingError: error
        )
        print("[SwiftFlow][LiveNodePoster] event=captureFailed \(failure)")
    }
}

#elseif os(iOS)
import UIKit

@MainActor
private struct PlatformMountedViewSnapshotHost: UIViewRepresentable {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let isSurfaceVisible: Bool
    let registry: LiveNodeSnapshotRegistry
    let snapshotProviderReady: () -> Void

    func makeUIView(context: Context) -> MountedViewSnapshotUIView {
        MountedViewSnapshotUIView()
    }

    func updateUIView(_ uiView: MountedViewSnapshotUIView, context: Context) {
        uiView.update(
            nodeID: nodeID,
            size: size,
            scale: scale,
            isSurfaceVisible: isSurfaceVisible,
            registry: registry,
            snapshotProviderReady: snapshotProviderReady
        )
    }

    static func dismantleUIView(_ uiView: MountedViewSnapshotUIView, coordinator: ()) {
        uiView.unregisterSnapshotProvider()
    }
}

@MainActor
private final class MountedViewSnapshotUIView: UIView {
    private let token = UUID()
    private weak var registry: LiveNodeSnapshotRegistry?
    private var nodeID: String = ""
    private var snapshotSize: CGSize = .zero
    private var snapshotScale: CGFloat = 1
    private var isSurfaceVisible = false
    private var snapshotProviderReady: (() -> Void)?
    private var didNotifySnapshotProviderReady = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        nodeID: String,
        size: CGSize,
        scale: CGFloat,
        isSurfaceVisible: Bool,
        registry: LiveNodeSnapshotRegistry,
        snapshotProviderReady: @escaping () -> Void
    ) {
        self.nodeID = nodeID
        snapshotSize = size
        snapshotScale = scale
        self.isSurfaceVisible = isSurfaceVisible
        self.snapshotProviderReady = snapshotProviderReady
        self.registry = registry
        registry.setMountedViewSnapshotProvider(token: token) { [weak self] in
            guard let self else { return nil }
            do {
                return try self.snapshotMountedNode()
            } catch {
                self.traceFailure(error)
                return nil
            }
        }
        notifySnapshotProviderReadyIfPossible()
    }

    func unregisterSnapshotProvider() {
        registry?.clearMountedViewSnapshotProvider(token: token)
        registry = nil
        didNotifySnapshotProviderReady = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifySnapshotProviderReadyIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        notifySnapshotProviderReadyIfPossible()
    }

    private func snapshotMountedNode() throws -> FlowNodeSnapshot {
        guard isSurfaceVisible else {
            throw LiveNodeSnapshotCaptureError.surfaceNotVisible
        }
        guard let targetView = snapshotTargetView() else {
            throw LiveNodeSnapshotCaptureError.windowUnavailable
        }
        let captureBounds = convert(bounds, to: targetView)
        guard captureBounds.width > 1, captureBounds.height > 1 else {
            throw LiveNodeSnapshotCaptureError.invalidLogicalSize(captureBounds.size)
        }

        targetView.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshotScale
        format.opaque = targetView.isOpaque

        var didDraw = false
        let renderer = UIGraphicsImageRenderer(size: captureBounds.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -captureBounds.minX, y: -captureBounds.minY)
            didDraw = targetView.drawHierarchy(
                in: targetView.bounds,
                afterScreenUpdates: true
            )
        }
        guard didDraw, let cgImage = image.cgImage else {
            throw LiveNodeSnapshotCaptureError.renderingFailed
        }
        let snapshot = FlowNodeSnapshot(cgImage: cgImage, scale: snapshotScale)
        try LiveNodeSnapshotQuality.validate(
            snapshot,
            logicalSize: snapshotSize,
            requiredScale: snapshotScale
        )
        return snapshot
    }

    private func snapshotTargetView() -> UIView? {
        var child: UIView = self
        var current = superview
        var sizedFallback: UIView?

        while let view = current {
            let captureBounds = convert(bounds, to: view)
            guard view.bounds.intersects(captureBounds) else {
                child = view
                current = view.superview
                continue
            }

            if isNodeSizedTarget(view, captureBounds: captureBounds) {
                sizedFallback = sizedFallback ?? view
                if hasVisibleContentSibling(
                    in: view,
                    excluding: child,
                    captureBounds: captureBounds
                ) {
                    return view
                }
            }

            child = view
            current = view.superview
        }

        return sizedFallback
    }

    private func isNodeSizedTarget(_ view: UIView, captureBounds: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        let widthAllowance = max(16, captureBounds.width * 0.25)
        let heightAllowance = max(16, captureBounds.height * 0.25)
        return view.bounds.width <= captureBounds.width + widthAllowance
            && view.bounds.height <= captureBounds.height + heightAllowance
            && captureBounds.minX >= view.bounds.minX - tolerance
            && captureBounds.minY >= view.bounds.minY - tolerance
            && captureBounds.maxX <= view.bounds.maxX + tolerance
            && captureBounds.maxY <= view.bounds.maxY + tolerance
    }

    private func hasVisibleContentSibling(
        in view: UIView,
        excluding child: UIView,
        captureBounds: CGRect
    ) -> Bool {
        view.subviews.contains { sibling in
            sibling !== child
                && !sibling.isHidden
                && sibling.alpha > 0.001
                && sibling.frame.intersects(captureBounds)
        }
    }

    private func notifySnapshotProviderReadyIfPossible() {
        guard window != nil else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard !didNotifySnapshotProviderReady else { return }
        didNotifySnapshotProviderReady = true
        Task { @MainActor [weak self] in
            self?.snapshotProviderReady?()
        }
    }

    private func traceFailure(_ error: Error) {
        let failure = LiveNodeSnapshotFailure(
            nodeID: nodeID,
            stage: .mountedViewCapture,
            underlyingError: error
        )
        print("[SwiftFlow][LiveNodePoster] event=captureFailed \(failure)")
    }
}
#endif
