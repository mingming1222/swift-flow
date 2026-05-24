#if os(macOS)

import SwiftUI

struct CanvasHoverTrackingView: NSViewRepresentable {

    let onHover: @MainActor (CGPoint) -> Void
    let onExit: @MainActor () -> Void
    let cursorAt: @MainActor (CGPoint) -> NSCursor
    let onMagnify: @MainActor (CGFloat, CGPoint) -> Void
    let shouldHandleViewportMagnify: @MainActor (CGPoint) -> Bool

    func makeNSView(context: Context) -> CanvasHoverTrackingNSView {
        let view = CanvasHoverTrackingNSView()
        view.onHover = onHover
        view.onExit = onExit
        view.cursorAt = cursorAt
        view.onMagnify = onMagnify
        view.shouldHandleViewportMagnify = shouldHandleViewportMagnify
        return view
    }

    func updateNSView(_ nsView: CanvasHoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onExit = onExit
        nsView.cursorAt = cursorAt
        nsView.onMagnify = onMagnify
        nsView.shouldHandleViewportMagnify = shouldHandleViewportMagnify
    }
}

final class CanvasHoverTrackingNSView: NSView {

    var onHover: (@MainActor (CGPoint) -> Void)?
    var onExit: (@MainActor () -> Void)?
    var cursorAt: (@MainActor (CGPoint) -> NSCursor)?
    var onMagnify: (@MainActor (CGFloat, CGPoint) -> Void)?
    var shouldHandleViewportMagnify: (@MainActor (CGPoint) -> Bool)?

    private var trackingArea: NSTrackingArea?
    private var magnifyMonitor: Any?

    deinit {
        MainActor.assumeIsolated {
            removeEventMonitors()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitorsIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverAndCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverAndCursor(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverAndCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isMouseInsideBounds() else {
            return
        }
        MainActor.assumeIsolated {
            onExit?()
        }
    }

    private func installEventMonitorsIfNeeded() {
        if magnifyMonitor == nil {
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                self?.handleViewportMagnify(event) ?? event
            }
        }
    }

    private func removeEventMonitors() {
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
    }

    private func handleViewportMagnify(_ event: NSEvent) -> NSEvent? {
        guard let location = viewportMagnifyLocation(from: event) else {
            return event
        }

        MainActor.assumeIsolated {
            onMagnify?(event.magnification, location)
        }
        return nil
    }

    private func viewportMagnifyLocation(from event: NSEvent) -> CGPoint? {
        guard event.window === window else {
            return nil
        }
        let location = flippedLocation(from: event)
        guard bounds.contains(CGPoint(x: location.x, y: bounds.height - location.y)) else {
            return nil
        }
        var shouldHandle = false
        MainActor.assumeIsolated {
            shouldHandle = shouldHandleViewportMagnify?(location) ?? false
        }
        return shouldHandle ? location : nil
    }

    private func updateHoverAndCursor(for event: NSEvent) {
        let location = flippedLocation(from: event)
        MainActor.assumeIsolated {
            onHover?(location)
            (cursorAt?(location) ?? .arrow).set()
        }
    }

    private func flippedLocation(from event: NSEvent) -> CGPoint {
        let location = convert(event.locationInWindow, from: nil)
        return CGPoint(x: location.x, y: bounds.height - location.y)
    }

    private func isMouseInsideBounds() -> Bool {
        guard let window else { return false }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(location)
    }
}

#endif
