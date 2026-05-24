import CoreGraphics
import Foundation
import SwiftUI

@MainActor
struct LiveNodeMountedViewSnapshotHost<SnapshotContent: View>: View {
    let size: CGSize
    let scale: CGFloat
    let registry: LiveNodeSnapshotRegistry
    let swiftUIEnvironment: EnvironmentValues
    let snapshotProviderReady: () -> Void
    let content: () -> SnapshotContent

    var body: some View {
        PlatformMountedViewSnapshotHost(
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
        size: CGSize,
        scale: CGFloat,
        registry: LiveNodeSnapshotRegistry,
        swiftUIEnvironment: EnvironmentValues,
        snapshotProviderReady: @escaping () -> Void,
        content: @escaping () -> SnapshotContent
    ) {
        snapshotSize = size
        snapshotScale = scale
        self.snapshotProviderReady = snapshotProviderReady
        self.registry = registry
        registry.setMountedViewSnapshotProvider(token: token) { [weak self] in
            guard let self else { return nil }
            return await LiveNodeIsolatedSnapshotRenderer.render(
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
        size: CGSize,
        scale: CGFloat,
        swiftUIEnvironment: EnvironmentValues,
        content: @escaping () -> SnapshotContent
    ) async -> FlowNodeSnapshot? {
        guard size.width > 1, size.height > 1 else { return nil }

        let hostingView = NSHostingView(
            rootView: content()
                .frame(width: size.width, height: size.height)
                .environment(\.self, swiftUIEnvironment)
                .environment(\.liveNodePosterContext, nil)
                .environment(\.defersLiveNodeSnapshotWrites, true)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: offscreenFrame(size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.ignoresCycle, .stationary]
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
            return try await captureWindow(window, size: size, scale: scale)
        } catch {
            return nil
        }
    }

    private static func offscreenFrame(size: CGSize) -> CGRect {
        let screenFrame = NSScreen.screens.first?.frame ?? .zero
        return CGRect(
            x: screenFrame.maxX + 4096,
            y: screenFrame.maxY + 4096,
            width: size.width,
            height: size.height
        )
    }

    private static func captureWindow(
        _ window: NSWindow,
        size: CGSize,
        scale: CGFloat
    ) async throws -> FlowNodeSnapshot {
        let cgImage = try await captureImage(
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
        windowID: CGWindowID,
        size: CGSize,
        scale: CGFloat
    ) async throws -> CGImage {
        let scWindow = try await shareableWindow(for: windowID)
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
                    continuation.resume(returning: image)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(throwing: CaptureError.imageUnavailable)
            }
        }
    }

    private static func shareableWindow(for windowID: CGWindowID) async throws -> SCWindow {
        for _ in 0..<10 {
            let content = try await shareableContent()
            if let window = content.windows.first(where: { $0.windowID == windowID }) {
                return window
            }
            guard await waitForFrame() else {
                throw CaptureError.windowUnavailable
            }
        }
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
