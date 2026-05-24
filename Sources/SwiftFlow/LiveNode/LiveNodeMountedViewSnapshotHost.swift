import CoreGraphics
import Foundation
import SwiftUI

@MainActor
struct LiveNodeMountedViewSnapshotHost<SnapshotContent: View>: View {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let registry: LiveNodeSnapshotRegistry
    let swiftUIEnvironment: EnvironmentValues
    let snapshotProviderReady: () -> Void
    let content: () -> SnapshotContent

    var body: some View {
        PlatformMountedViewSnapshotHost(
            nodeID: nodeID,
            size: size,
            scale: scale,
            registry: registry,
            swiftUIEnvironment: swiftUIEnvironment,
            snapshotProviderReady: snapshotProviderReady,
            content: content
        )
        .frame(width: size.width, height: size.height)
    }
}

#if os(macOS)
import AppKit
import ScreenCaptureKit

@MainActor
private struct PlatformMountedViewSnapshotHost<SnapshotContent: View>: NSViewRepresentable {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let registry: LiveNodeSnapshotRegistry
    let swiftUIEnvironment: EnvironmentValues
    let snapshotProviderReady: () -> Void
    let content: () -> SnapshotContent

    func makeNSView(context: Context) -> MountedViewSnapshotNSView {
        MountedViewSnapshotNSView()
    }

    func updateNSView(_ nsView: MountedViewSnapshotNSView, context: Context) {
        nsView.update(
            nodeID: nodeID,
            size: size,
            scale: scale,
            registry: registry,
            swiftUIEnvironment: swiftUIEnvironment,
            snapshotProviderReady: snapshotProviderReady,
            content: content
        )
    }

    static func dismantleNSView(_ nsView: MountedViewSnapshotNSView, coordinator: ()) {
        nsView.unregisterSnapshotProvider()
    }
}

@MainActor
private final class MountedViewSnapshotNSView: NSView {
    private let token = UUID()
    private weak var registry: LiveNodeSnapshotRegistry?
    private var nodeID: String = ""
    private var snapshotSize: CGSize = .zero
    private var snapshotScale: CGFloat = 2
    private var snapshotProviderReady: (() -> Void)?
    private var didNotifySnapshotProviderReady = false

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func update<SnapshotContent: View>(
        nodeID: String,
        size: CGSize,
        scale: CGFloat,
        registry: LiveNodeSnapshotRegistry,
        swiftUIEnvironment: EnvironmentValues,
        snapshotProviderReady: @escaping () -> Void,
        content: @escaping () -> SnapshotContent
    ) {
        self.nodeID = nodeID
        snapshotSize = size
        snapshotScale = scale
        self.snapshotProviderReady = snapshotProviderReady
        self.registry = registry
        registry.setMountedViewSnapshotProvider(token: token) { [weak self] in
            guard let self else { return nil }
            return await LiveNodeIsolatedSnapshotRenderer.render(
                nodeID: self.nodeID,
                size: self.snapshotSize,
                scale: self.snapshotScale,
                swiftUIEnvironment: swiftUIEnvironment,
                content: content
            )
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

    private func notifySnapshotProviderReadyIfPossible() {
        guard window != nil else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard !didNotifySnapshotProviderReady else { return }
        didNotifySnapshotProviderReady = true
        Task { @MainActor [weak self] in
            self?.snapshotProviderReady?()
        }
    }

}

@MainActor
private enum LiveNodeIsolatedSnapshotRenderer {

    enum CaptureError: Error {
        case windowUnavailable
        case shareableWindowUnavailable
        case imageUnavailable
    }

    static func render<SnapshotContent: View>(
        nodeID: String,
        size: CGSize,
        scale: CGFloat,
        swiftUIEnvironment: EnvironmentValues,
        content: @escaping () -> SnapshotContent
    ) async -> FlowNodeSnapshot? {
        guard size.width > 1, size.height > 1 else {
            print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=mountedRender skipped=invalidSize size=\(size)")
            return nil
        }

        let layout = captureLayout(size: size, targetScale: scale)

        print(
            "[SwiftFlow][LiveNodePoster] node=\(nodeID) event=mountedRender start "
                + "size=\(size) scale=\(layout.targetScale) backingScale=\(layout.backingScale) "
                + "renderScale=\(layout.renderScale)"
        )

        let hostingView = NSHostingView(
            rootView: content()
                .frame(width: size.width, height: size.height)
                .environment(\.self, swiftUIEnvironment)
                .environment(\.displayScale, layout.targetScale)
                .environment(\.liveNodePosterContext, nil)
                .environment(\.defersLiveNodeSnapshotWrites, true)
                .scaleEffect(layout.renderScale, anchor: .topLeading)
                .frame(
                    width: layout.renderSize.width,
                    height: layout.renderSize.height,
                    alignment: .topLeading
                )
        )
        hostingView.frame = CGRect(origin: .zero, size: layout.renderSize)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: layout.windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=mountedRender windowFrame=\(window.frame)")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<20 {
            await Task.yield()
            guard await waitForFrame() else { return nil }
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }

        do {
            let snapshot = try await captureWindow(window, nodeID: nodeID, size: size, scale: layout.targetScale)
            print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=mountedRender captured")
            return snapshot
        } catch {
            print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=mountedRender failed error=\(error)")
            return nil
        }
    }

    private struct CaptureLayout {
        let targetScale: CGFloat
        let backingScale: CGFloat
        let renderScale: CGFloat
        let renderSize: CGSize
        let windowFrame: CGRect
    }

    private static func captureLayout(size: CGSize, targetScale: CGFloat) -> CaptureLayout {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let backingScale = max(1, screen?.backingScaleFactor ?? 1)
        let targetScale = max(1, targetScale)
        let renderScale = max(1, targetScale / backingScale)
        let renderSize = CGSize(
            width: max(1, (size.width * renderScale).rounded(.up)),
            height: max(1, (size.height * renderScale).rounded(.up))
        )

        return CaptureLayout(
            targetScale: targetScale,
            backingScale: backingScale,
            renderScale: renderScale,
            renderSize: renderSize,
            windowFrame: captureFrame(size: renderSize, screen: screen)
        )
    }

    private static func captureFrame(size: CGSize, screen: NSScreen?) -> CGRect {
        let screenFrame = screen?.frame ?? CGRect(origin: .zero, size: size)
        let width = max(1, size.width.rounded(.up))
        let height = max(1, size.height.rounded(.up))
        let originX = screenFrame.minX + max(0, (screenFrame.width - width) / 2)
        let originY = screenFrame.minY + max(0, (screenFrame.height - height) / 2)
        return CGRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
    }

    private static func captureWindow(
        _ window: NSWindow,
        nodeID: String,
        size: CGSize,
        scale: CGFloat
    ) async throws -> FlowNodeSnapshot {
        let cgImage = try await captureImage(
            nodeID: nodeID,
            windowID: CGWindowID(window.windowNumber),
            size: size,
            scale: scale
        )
        let imageScale = CGFloat(cgImage.width) / max(1, size.width)
        guard imageScale.isFinite, imageScale > 0 else {
            throw CaptureError.imageUnavailable
        }
        return FlowNodeSnapshot(cgImage: cgImage, scale: imageScale)
    }

    private static func captureImage(
        nodeID: String,
        windowID: CGWindowID,
        size: CGSize,
        scale: CGFloat
    ) async throws -> CGImage {
        print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=screenCapture start windowID=\(windowID) size=\(size)")
        let scWindow = try await shareableWindow(for: windowID, nodeID: nodeID)
        print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=screenCapture filter windowID=\(scWindow.windowID) frame=\(scWindow.frame)")
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((size.width * scale).rounded(.toNearestOrAwayFromZero)))
        configuration.height = max(1, Int((size.height * scale).rounded(.toNearestOrAwayFromZero)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.showsCursor = false

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let image {
                    print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=screenCapture success pixels=\(image.width)x\(image.height)")
                    continuation.resume(returning: image)
                    return
                }
                if let error {
                    print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=screenCapture failed error=\(error)")
                    continuation.resume(throwing: error)
                    return
                }
                print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=screenCapture failed error=imageUnavailable")
                continuation.resume(throwing: CaptureError.imageUnavailable)
            }
        }
    }

    private static func shareableWindow(for windowID: CGWindowID, nodeID: String) async throws -> SCWindow {
        for attempt in 0..<10 {
            let content = try await shareableContent()
            if let window = content.windows.first(where: { $0.windowID == windowID }) {
                print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=shareableWindow found attempt=\(attempt) frame=\(window.frame)")
                return window
            }
            print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=shareableWindow missing attempt=\(attempt) windowCount=\(content.windows.count)")
            guard await waitForFrame() else {
                throw CaptureError.windowUnavailable
            }
        }
        print("[SwiftFlow][LiveNodePoster] node=\(nodeID) event=shareableWindow unavailable windowID=\(windowID)")
        throw CaptureError.shareableWindowUnavailable
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            let content = try await SCShareableContent.currentProcess
            if !content.windows.isEmpty {
                return content
            }
        } catch {
            // Fall through to the explicit offscreen-capable query below.
        }

        return try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
    }

    private static func waitForFrame() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: 16_000_000)
            return true
        } catch {
            return false
        }
    }
}

#elseif os(iOS)
import UIKit

@MainActor
private struct PlatformMountedViewSnapshotHost<SnapshotContent: View>: UIViewRepresentable {
    let nodeID: String
    let size: CGSize
    let scale: CGFloat
    let registry: LiveNodeSnapshotRegistry
    let swiftUIEnvironment: EnvironmentValues
    let snapshotProviderReady: () -> Void
    let content: () -> SnapshotContent

    func makeUIView(context: Context) -> MountedViewSnapshotUIView {
        MountedViewSnapshotUIView()
    }

    func updateUIView(_ uiView: MountedViewSnapshotUIView, context: Context) {
        uiView.update(
            scale: scale,
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
    private var snapshotScale: CGFloat = 2
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
        scale: CGFloat,
        registry: LiveNodeSnapshotRegistry,
        snapshotProviderReady: @escaping () -> Void
    ) {
        snapshotScale = scale
        self.snapshotProviderReady = snapshotProviderReady
        self.registry = registry
        registry.setMountedViewSnapshotProvider(token: token) { [weak self] in
            self?.snapshotMountedNode()
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

    private func notifySnapshotProviderReadyIfPossible() {
        guard window != nil else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard !didNotifySnapshotProviderReady else { return }
        didNotifySnapshotProviderReady = true
        Task { @MainActor [weak self] in
            self?.snapshotProviderReady?()
        }
    }

    private func snapshotMountedNode() -> FlowNodeSnapshot? {
        guard let targetView = snapshotTargetView() else { return nil }
        let captureBounds = convert(bounds, to: targetView)
        guard captureBounds.width > 1, captureBounds.height > 1 else { return nil }

        targetView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshotScale
        format.opaque = targetView.isOpaque

        let renderer = UIGraphicsImageRenderer(size: captureBounds.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -captureBounds.minX, y: -captureBounds.minY)
            targetView.drawHierarchy(in: targetView.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else {
            return nil
        }
        return FlowNodeSnapshot(cgImage: cgImage, scale: image.scale)
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
                if hasVisibleContentSibling(in: view, excluding: child, captureBounds: captureBounds) {
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
}

#endif
