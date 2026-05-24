#if os(macOS)

import SwiftUI

struct CanvasHoverTrackingView: NSViewRepresentable {

    let onHover: @MainActor (CGPoint) -> Void
    let onExit: @MainActor () -> Void
    let cursorAt: @MainActor (CGPoint) -> NSCursor

    func makeNSView(context: Context) -> CanvasHoverTrackingNSView {
        let view = CanvasHoverTrackingNSView()
        view.onHover = onHover
        view.onExit = onExit
        view.cursorAt = cursorAt
        return view
    }

    func updateNSView(_ nsView: CanvasHoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onExit = onExit
        nsView.cursorAt = cursorAt
    }
}

final class CanvasHoverTrackingNSView: NSView {

    var onHover: (@MainActor (CGPoint) -> Void)?
    var onExit: (@MainActor () -> Void)?
    var cursorAt: (@MainActor (CGPoint) -> NSCursor)?

    private var trackingArea: NSTrackingArea?

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
